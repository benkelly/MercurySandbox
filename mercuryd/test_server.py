"""Unit tests for mercuryd: validation, auth and the HTTP surface with a
stubbed Runner. Run with: python3 -m unittest discover -s mercuryd"""
import json
import threading
import unittest
import urllib.error
import urllib.request

import server


class FakeRunner:
    def __init__(self):
        self.killed = []
        self.spawned = []

    def docker_ok(self):
        return True

    def models(self):
        return ["cheap-default", "claude-sonnet"]

    def gateway_ok(self):
        return True, "ok"

    def sandboxes(self):
        return [{"name": "mercury-20260101-000000-ab12", "status": "running", "started": "2026",
                 "repo": "https://example.com/r.git", "branch": "agent/x", "model": "cheap-default", "task": "t"}]

    def spawn(self, fields):
        self.spawned.append(fields)
        return "mercury-20260101-000000-cd34"

    def logs(self, name, tail):
        return f"logs of {name} tail={tail}\n"

    def kill(self, name):
        self.killed.append(name)


class ValidationTests(unittest.TestCase):
    def test_spawn_ok(self):
        f = server.validate_spawn({"repo": "https://github.com/a/b.git", "task": "do it"}, "cheap-default")
        self.assertEqual(f["model"], "cheap-default")
        self.assertEqual(f["branch"], "")

    def test_spawn_rejects_bad_repo(self):
        for repo in ["", "ftp://x", "https://x; rm -rf /", "file:///etc/passwd"]:
            with self.assertRaises(server.BadRequest):
                server.validate_spawn({"repo": repo, "task": "x"}, "m")

    def test_spawn_requires_task(self):
        with self.assertRaises(server.BadRequest):
            server.validate_spawn({"repo": "https://x/y", "task": "  "}, "m")

    def test_spawn_rejects_odd_model_and_branch(self):
        with self.assertRaises(server.BadRequest):
            server.validate_spawn({"repo": "https://x/y", "task": "t", "model": "a b"}, "m")
        with self.assertRaises(server.BadRequest):
            server.validate_spawn({"repo": "https://x/y", "task": "t", "branch": "-bad"}, "m")

    def test_name(self):
        self.assertEqual(server.validate_name("mercury-20260101-000000-ab12"), "mercury-20260101-000000-ab12")
        for bad in ["gateway", "mercury-../x", "mercury-a b", "../etc"]:
            with self.assertRaises(server.BadRequest):
                server.validate_name(bad)


class AuthTests(unittest.TestCase):
    def cfg(self, **env):
        return server.Config(env)

    def test_open_by_default(self):
        self.assertTrue(self.cfg().authorized("10.0.0.5", None))

    def test_token_required_when_set(self):
        c = self.cfg(MERCURY_API_TOKEN="s3cret")
        self.assertFalse(c.authorized("10.0.0.5", None))
        self.assertFalse(c.authorized("10.0.0.5", "Bearer wrong"))
        self.assertTrue(c.authorized("10.0.0.5", "Bearer s3cret"))

    def test_ingress_only(self):
        c = self.cfg(MERCURY_INGRESS_ONLY="1", MERCURY_TRUSTED_PROXY="172.30.32.2")
        self.assertFalse(c.authorized("192.168.1.9", None))
        self.assertTrue(c.authorized("172.30.32.2", None))

    def test_trusted_proxy_bypasses_token(self):
        c = self.cfg(MERCURY_API_TOKEN="s3cret", MERCURY_TRUSTED_PROXY="172.30.32.2")
        self.assertTrue(c.authorized("172.30.32.2", None))
        self.assertFalse(c.authorized("172.30.32.3", None))

    def test_gateway_url_defaults(self):
        self.assertEqual(self.cfg().gateway_url, "http://127.0.0.1:4000/v1")
        self.assertEqual(self.cfg(GATEWAY_PORT="4100").gateway_url, "http://127.0.0.1:4100/v1")
        self.assertEqual(self.cfg(MERCURY_IN_CONTAINER="1").gateway_url, "http://gateway:4000/v1")


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = FakeRunner()
        cfg = server.Config({"MERCURY_BIND": "127.0.0.1", "MERCURY_PORT": "0", "MERCURY_API_TOKEN": "tok"})
        cls.srv = server.make_server(cfg, cls.runner)
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_address[1]
        cls.thread = threading.Thread(target=cls.srv.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def call(self, method, path, body=None, auth=True):
        req = urllib.request.Request(self.base + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Content-Type", "application/json")
        if auth:
            req.add_header("Authorization", "Bearer tok")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, r.read().decode(), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(), e.headers.get("Content-Type", "")

    def test_page_and_health_are_open(self):
        status, body, ctype = self.call("GET", "/", auth=False)
        self.assertEqual(status, 200)
        self.assertIn("text/html", ctype)
        self.assertIn("MercurySandbox", body)
        status, body, _ = self.call("GET", "/api/health", auth=False)
        self.assertEqual((status, json.loads(body)), (200, {"ok": True}))

    def test_api_needs_token(self):
        self.assertEqual(self.call("GET", "/api/status", auth=False)[0], 401)
        self.assertEqual(self.call("POST", "/api/sandboxes", {"repo": "https://x/y", "task": "t"}, auth=False)[0], 401)
        self.assertEqual(self.call("DELETE", "/api/sandboxes/mercury-x", auth=False)[0], 401)

    def test_status(self):
        status, body, _ = self.call("GET", "/api/status")
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertTrue(data["docker"])
        self.assertEqual(data["models"], ["cheap-default", "claude-sonnet"])
        self.assertEqual(len(data["sandboxes"]), 1)
        self.assertEqual(data["auth"], "token")

    def test_spawn_and_kill(self):
        status, body, _ = self.call("POST", "/api/sandboxes", {"repo": "https://x/y.git", "task": "add tests", "model": "claude-sonnet"})
        self.assertEqual(status, 201, body)
        self.assertEqual(json.loads(body)["name"], "mercury-20260101-000000-cd34")
        self.assertEqual(self.runner.spawned[-1]["model"], "claude-sonnet")
        status, body, _ = self.call("DELETE", "/api/sandboxes/mercury-20260101-000000-cd34")
        self.assertEqual(status, 200)
        self.assertIn("mercury-20260101-000000-cd34", self.runner.killed)

    def test_spawn_validation_error(self):
        status, body, _ = self.call("POST", "/api/sandboxes", {"repo": "nope", "task": "t"})
        self.assertEqual(status, 400)
        self.assertIn("repo", json.loads(body)["error"])

    def test_logs(self):
        status, body, ctype = self.call("GET", "/api/sandboxes/mercury-20260101-000000-ab12/logs?tail=50")
        self.assertEqual(status, 200)
        self.assertIn("text/plain", ctype)
        self.assertEqual(body, "logs of mercury-20260101-000000-ab12 tail=50\n")

    def test_unknown_paths(self):
        self.assertEqual(self.call("GET", "/api/nope")[0], 404)
        self.assertEqual(self.call("DELETE", "/api/sandboxes/gateway")[0], 400)


if __name__ == "__main__":
    unittest.main()
