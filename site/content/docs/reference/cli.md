---
title: The mercury CLI
weight: 1
description: Every subcommand of bin/mercury.
---

`bin/mercury` on a host, `mercury` inside the controller image. `mercury -H you@host <cmd>` (or `MERCURY_HOST`) runs any of these on a remote host over SSH.

## Stack

| Command | Does |
|---|---|
| `mercury up [--pull]` | `docker compose up -d --build` the gateway and controller; enables the tunnel profile if a token is set, layers the virtual-key database if enabled; builds or pulls the sandbox image. Idempotent. |
| `mercury down [--force]` | `docker compose down`. Refuses while sandboxes run. |
| `mercury stop` | Stop the services, keep everything for the next `up`. |
| `mercury status` | Compose services and running sandboxes. |
| `mercury doctor` | Read-only checks: Docker, compose, env, keys, credentials mode, gateway, network, image, old sandboxes. Exit 1 on any FAIL. |
| `mercury models` | Model names the gateway exposes. |
| `mercury logs [--tail N] [--no-follow] <gateway\|mercury\|cloudflared\|gateway-db\|sandbox>` | Follow a service or a sandbox. |

## Sandboxes

```
mercury sandbox [options] <git-url> [task] [model]
```

| Option | Does |
|---|---|
| `-d`, `--detach` | Background; prints the sandbox name. Needs a task. |
| `--model <name>` | A `model_name` from the gateway routing. Default `SANDBOX_DEFAULT_MODEL` or `cheap-default`. |
| `--branch <name>` | Work branch to push. Default `agent/<timestamp>-<id>`. |
| `--base <branch>` | Branch to clone. Default: the remote's default branch. |
| `--context <text>` | Appended to the prompt. `@path` reads a file. |
| `--timeout <secs>` | Stop opencode after this long. Default `SANDBOX_TIMEOUT` or 3600. |
| `--budget <usd>` | Spend cap for this sandbox's key (virtual keys only). |
| `--open-pr` | Open a GitHub pull request after pushing. |
| `--no-push` | Commit but never push. |
| `--shell` | bash in a fresh sandbox instead of opencode (Docker backend). |

No task and no `--detach` gives the interactive opencode TUI (Docker backend only).

| Command | Does |
|---|---|
| `mercury ps [--json]` | Running sandboxes. `--json` is what the API and page use. |
| `mercury exec <name> [cmd…]` | Shell into a running sandbox (default `bash`). |
| `mercury kill <name>` | Stop a sandbox; it deletes itself. |

## Other

| Command | Does |
|---|---|
| `mercury serve` | Run mercuryd (the API and page) in the foreground. |
| `mercury install <hermes\|webui\|ocm>` | Native install scripts for the optional pieces. |
| `mercury version` | Print the version. |

## Backend

`SANDBOX_BACKEND=docker` (default) or `kubernetes`. Every sandbox command works the same on either; the TUI and `--shell` are Docker-only.
