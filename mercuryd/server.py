#!/usr/bin/env python3
"""mercuryd: a small HTTP API and web page over the mercury CLI.

Standard library only, so it runs wherever python3 does: on the host
(`mercury serve`), in the controller image, and inside the Home Assistant
add-on behind ingress. Everything that touches Docker goes through the same
`mercury` CLI and `docker` commands a person would run, so there is exactly
one definition of how a sandbox is hardened (lib/sandbox.sh).

Endpoints (all JSON unless noted):
  GET    /                      the web page
  GET    /api/health            liveness, never authenticated
  GET    /api/status            docker, gateway, models and sandboxes in one call
  GET    /api/models            model names the gateway exposes
  GET    /api/sandboxes         running sandboxes
  POST   /api/sandboxes         {repo, task, model?, branch?, base?} -> {name}
  GET    /api/sandboxes/<name>/logs?tail=N   text/plain
  DELETE /api/sandboxes/<name>  stop it (it self-deletes)

Auth, in order:
  - /api/health and the page are always open (they leak nothing).
  - Requests from MERCURY_TRUSTED_PROXY (the Home Assistant ingress proxy)
    are trusted: ingress has already authenticated the person.
  - If MERCURY_API_TOKEN is set, everything else needs
    "Authorization: Bearer <token>".
  - If MERCURY_INGRESS_ONLY=1, everything else is refused outright.
  - Otherwise (a laptop, bound to loopback) requests are accepted.
"""
from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

log = logging.getLogger("mercuryd")

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("MERCURY_ROOT") or HERE.parent)
UI_FILE = HERE / "ui.html"

NAME_RE = re.compile(r"^mercury-[A-Za-z0-9][A-Za-z0-9_.-]{0,80}$")
MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,120}$")
BRANCH_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,200}$")
REPO_RE = re.compile(r"^(https?://|ssh://|git@)[^\s'\"`$;|&<>]+$")
MAX_TASK = 8000


class Config:
    """Runtime configuration, read once from the environment."""

    def __init__(self, env=os.environ):
        self.bind = env.get("MERCURY_BIND", "127.0.0.1")
        self.port = int(env.get("MERCURY_PORT", "5004"))
        self.token = env.get("MERCURY_API_TOKEN", "").strip()
        self.trusted_proxy = env.get("MERCURY_TRUSTED_PROXY", "").strip()
        self.ingress_only = env.get("MERCURY_INGRESS_ONLY", "0") == "1"
        self.master_key = env.get("LITELLM_MASTER_KEY", "")
        self.default_model = env.get("SANDBOX_DEFAULT_MODEL", "cheap-default")
        in_container = env.get("MERCURY_IN_CONTAINER", "0") == "1"
        self.gateway_url = env.get("MERCURY_GATEWAY_URL") or (
            "http://gateway:4000/v1"
            if in_container
            else f"http://127.0.0.1:{env.get('GATEWAY_PORT', '4000')}/v1"
        )
        self.mercury = str(ROOT / "bin" / "mercury")

    def authorized(self, client_ip: str, auth_header: str | None) -> bool:
        """Decide whether a request to a protected endpoint may proceed."""
        if self.trusted_proxy and client_ip == self.trusted_proxy:
            return True
        if self.token:
            return auth_header == f"Bearer {self.token}"
        if self.ingress_only:
            return False
        return True


# ---- validation --------------------------------------------------------------


class BadRequest(ValueError):
    pass


def validate_spawn(body: dict, default_model: str) -> dict:
    """Check a spawn request and return the cleaned fields."""
    if not isinstance(body, dict):
        raise BadRequest("body must be a JSON object")
    repo = str(body.get("repo", "")).strip()
    task = str(body.get("task", "")).strip()
    model = str(body.get("model") or default_model).strip()
    branch = str(body.get("branch", "")).strip()
    base = str(body.get("base", "")).strip()
    if not REPO_RE.match(repo):
        raise BadRequest("repo must be an https://, ssh:// or git@ URL")
    if not task:
        raise BadRequest("task is required: a background sandbox needs something to do")
    if len(task) > MAX_TASK:
        raise BadRequest(f"task is longer than {MAX_TASK} characters")
    if not MODEL_RE.match(model):
        raise BadRequest("model name contains unexpected characters")
    if branch and not BRANCH_RE.match(branch):
        raise BadRequest("branch name contains unexpected characters")
    if base and not BRANCH_RE.match(base):
        raise BadRequest("base branch name contains unexpected characters")
    return {"repo": repo, "task": task, "model": model, "branch": branch, "base": base}


def validate_name(name: str) -> str:
    if not NAME_RE.match(name):
        raise BadRequest("not a sandbox name")
    return name


# ---- docker / gateway --------------------------------------------------------


class Runner:
    """Everything that shells out, kept in one class so tests can stub it."""

    def __init__(self, cfg: Config):
        self.cfg = cfg

    def run(self, argv: list[str], timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
        full_env = dict(os.environ)
        if env:
            full_env.update(env)
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=full_env, check=False)

    def docker_ok(self) -> bool:
        if not shutil.which("docker"):
            return False
        return self.run(["docker", "info"], timeout=15).returncode == 0

    def sandboxes(self) -> list[dict]:
        ids = self.run(["docker", "ps", "-q", "--filter", "label=mercury.sandbox"], timeout=20)
        if ids.returncode != 0:
            raise RuntimeError(ids.stderr.strip() or "docker ps failed")
        id_list = ids.stdout.split()
        if not id_list:
            return []
        inspect = self.run(["docker", "inspect", *id_list], timeout=20)
        if inspect.returncode != 0:
            raise RuntimeError(inspect.stderr.strip() or "docker inspect failed")
        out = []
        for c in json.loads(inspect.stdout):
            labels = c.get("Config", {}).get("Labels", {}) or {}
            state = c.get("State", {})
            out.append(
                {
                    "name": c.get("Name", "").lstrip("/"),
                    "status": state.get("Status"),
                    "started": state.get("StartedAt"),
                    "repo": labels.get("mercury.repo", ""),
                    "branch": labels.get("mercury.branch", ""),
                    "model": labels.get("mercury.model", ""),
                    "task": labels.get("mercury.task", ""),
                }
            )
        out.sort(key=lambda s: s["started"] or "", reverse=True)
        return out

    def spawn(self, fields: dict) -> str:
        argv = [self.cfg.mercury, "sandbox", "--detach", "--model", fields["model"]]
        if fields["branch"]:
            argv += ["--branch", fields["branch"]]
        if fields["base"]:
            argv += ["--base", fields["base"]]
        argv += ["--", fields["repo"], fields["task"]]
        p = self.run(argv, timeout=120)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip().splitlines()[-1] if p.stderr.strip() else "spawn failed")
        name = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else ""
        if not NAME_RE.match(name):
            raise RuntimeError("spawn returned no container name")
        return name

    def logs(self, name: str, tail: int) -> str:
        p = self.run(["docker", "logs", "--tail", str(tail), name], timeout=30)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "docker logs failed")
        return p.stdout + p.stderr

    def kill(self, name: str) -> None:
        p = self.run(["docker", "stop", "-t", "10", name], timeout=40)
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or "docker stop failed")

    def models(self) -> list[str]:
        req = urllib.request.Request(
            f"{self.cfg.gateway_url}/models",
            headers={"Authorization": f"Bearer {self.cfg.master_key}"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:  # noqa: S310 (fixed, non-user URL)
            data = json.load(resp)
        return sorted(m.get("id", "") for m in data.get("data", []) if m.get("id"))

    def gateway_ok(self) -> tuple[bool, str]:
        try:
            self.models()
            return True, "ok"
        except urllib.error.HTTPError as e:
            return False, f"gateway answered {e.code}"
        except (urllib.error.URLError, OSError, ValueError) as e:
            return False, f"gateway unreachable: {getattr(e, 'reason', e)}"


# ---- HTTP --------------------------------------------------------------------


class Handler(BaseHTTPRequestHandler):
    server_version = "mercuryd/" + (ROOT / "VERSION").read_text().strip() if (ROOT / "VERSION").exists() else "mercuryd/dev"
    cfg: Config
    runner: Runner

    # -- plumbing --
    def log_message(self, fmt, *args):  # quieter than the default, to stderr via logging
        log.info("%s %s", self.client_address[0], fmt % args)

    def send_json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status: int, text: str, ctype="text/plain; charset=utf-8") -> None:
        body = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length > 65536:
            raise BadRequest("request body too large")
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw or b"{}")
        except json.JSONDecodeError as e:
            raise BadRequest(f"invalid JSON: {e}") from e

    def guard(self) -> bool:
        if self.cfg.authorized(self.client_address[0], self.headers.get("Authorization")):
            return True
        self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        return False

    # -- routing --
    def do_GET(self):  # noqa: N802
        url = urlsplit(self.path)
        path = url.path.rstrip("/") or "/"
        if path in ("/", "/index.html"):
            return self.send_text(HTTPStatus.OK, UI_FILE.read_text(), "text/html; charset=utf-8")
        if path == "/api/health":
            return self.send_json(HTTPStatus.OK, {"ok": True})
        if not self.guard():
            return None
        try:
            if path == "/api/status":
                return self.send_json(HTTPStatus.OK, self.status())
            if path == "/api/models":
                return self.send_json(HTTPStatus.OK, {"models": self.runner.models()})
            if path == "/api/sandboxes":
                return self.send_json(HTTPStatus.OK, {"sandboxes": self.runner.sandboxes()})
            m = re.match(r"^/api/sandboxes/([^/]+)/logs$", path)
            if m:
                name = validate_name(m.group(1))
                tail = min(int(parse_qs(url.query).get("tail", ["300"])[0]), 5000)
                return self.send_text(HTTPStatus.OK, self.runner.logs(name, tail))
        except BadRequest as e:
            return self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
        except (RuntimeError, subprocess.TimeoutExpired, urllib.error.URLError, OSError, ValueError) as e:
            return self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(e)})
        return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        path = urlsplit(self.path).path.rstrip("/")
        if path != "/api/sandboxes":
            return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        if not self.guard():
            return None
        try:
            fields = validate_spawn(self.read_json(), self.cfg.default_model)
            name = self.runner.spawn(fields)
        except BadRequest as e:
            return self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
            return self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(e)})
        log.info("spawned %s for %s", name, fields["repo"])
        return self.send_json(HTTPStatus.CREATED, {"name": name, "branch": fields["branch"] or None})

    def do_DELETE(self):  # noqa: N802
        path = urlsplit(self.path).path.rstrip("/")
        m = re.match(r"^/api/sandboxes/([^/]+)$", path)
        if not m:
            return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        if not self.guard():
            return None
        try:
            name = validate_name(m.group(1))
            self.runner.kill(name)
        except BadRequest as e:
            return self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(e)})
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
            return self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(e)})
        log.info("stopped %s", name)
        return self.send_json(HTTPStatus.OK, {"stopped": name})

    # -- composite --
    def status(self) -> dict:
        docker = self.runner.docker_ok()
        gw_ok, gw_msg = self.runner.gateway_ok()
        models = self.runner.models() if gw_ok else []
        sandboxes = self.runner.sandboxes() if docker else []
        return {
            "version": self.server_version.split("/", 1)[1],
            "docker": docker,
            "gateway": {"ok": gw_ok, "detail": gw_msg, "url": self.cfg.gateway_url},
            "models": models,
            "default_model": self.cfg.default_model,
            "sandboxes": sandboxes,
            "auth": "token" if self.cfg.token else ("ingress" if self.cfg.ingress_only else "open"),
        }


def make_server(cfg: Config, runner: Runner | None = None) -> ThreadingHTTPServer:
    handler = type("BoundHandler", (Handler,), {"cfg": cfg, "runner": runner or Runner(cfg)})
    return ThreadingHTTPServer((cfg.bind, cfg.port), handler)


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="mercuryd: %(message)s", stream=sys.stderr)
    cfg = Config()
    if not UI_FILE.exists():
        log.error("ui.html missing next to server.py")
        return 1
    if cfg.bind not in ("127.0.0.1", "localhost", "::1") and not (cfg.token or cfg.trusted_proxy or cfg.ingress_only):
        log.warning("bound to %s with no MERCURY_API_TOKEN: anyone who reaches this port controls Docker", cfg.bind)
    srv = make_server(cfg)
    log.info("listening on http://%s:%d (gateway %s, auth: %s)", cfg.bind, cfg.port, cfg.gateway_url,
             "token" if cfg.token else ("ingress only" if cfg.ingress_only else "open"))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
