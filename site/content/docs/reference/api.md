---
title: The HTTP API
weight: 2
description: mercuryd, the standard-library server behind the web page.
---

mercuryd wraps the CLI. It runs as `mercury serve`, in the controller container on port 5004, behind Home Assistant ingress, and as the controller Deployment in the chart. Everything is JSON except logs.

| Method and path | Does |
|---|---|
| `GET /api/health` | Liveness, `{"ok": true}`. Never authenticated. |
| `GET /api/status` | Backend, gateway, models, virtual-keys flag and sandboxes in one call. |
| `GET /api/models` | `{"models": [...]}` from the gateway. |
| `GET /api/sandboxes` | `{"sandboxes": [...]}`, each with name, status, started, repo, branch, model, task, backend. |
| `POST /api/sandboxes` | Spawn. Body below. Returns `201 {"name": "...", "branch": ...}`. |
| `GET /api/sandboxes/<name>/logs?tail=N` | Plain text, last N lines (default 300, max 5000). |
| `DELETE /api/sandboxes/<name>` | Stop it. |

Spawn body:

```json
{
  "repo": "https://github.com/you/repo.git",
  "task": "add a /health endpoint with a test",
  "model": "claude-sonnet",
  "context": "The server lives in src/server.py; run make test.",
  "open_pr": true,
  "branch": "agent/health",
  "base": "main"
}
```

`repo` and `task` are required; the rest are optional. Validation errors come back as `400 {"error": "..."}`; failures talking to Docker, Kubernetes or the gateway as `502`.

## Authentication

In order:

1. `/api/health` and the page itself are always open.
2. Requests from `MERCURY_TRUSTED_PROXY` (Home Assistant's ingress proxy) are trusted: ingress has authenticated the person.
3. If `MERCURY_API_TOKEN` is set, everything else needs `Authorization: Bearer <token>`.
4. If `MERCURY_INGRESS_ONLY=1`, everything else is refused.
5. Otherwise (a laptop, bound to loopback) requests are accepted.

Whoever can call `POST /api/sandboxes` can run containers on the host, or Jobs in the namespace. Treat the token like an SSH key and keep the port on loopback or behind Tailscale.

```bash
curl -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"repo":"https://github.com/you/repo.git","task":"add a health endpoint"}' \
  http://127.0.0.1:5004/api/sandboxes
```
