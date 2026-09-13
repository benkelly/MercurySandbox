---
title: Troubleshooting
weight: 3
description: Start with mercury doctor. Then this page.
---

`mercury doctor` checks the things that usually go wrong and says what to do. When it does not, this page.

## The stack

**`mercury up` fails with "set LITELLM_MASTER_KEY in .env".** The `.env` is missing, empty, or still the placeholder. `cp .env.example .env` and fill it in.

**The gateway container restarts.** `mercury logs gateway`. A typo in `gateway/config.yaml` is the usual cause and LiteLLM names the line. A provider key that does not match the provider in the routing shows up as an error on the first model call instead.

**`mercury models` says the gateway is not answering.** It takes a minute to start. If it is still quiet after that, `mercury logs gateway`. From inside a container the gateway is `http://gateway:4000`, from the host `http://127.0.0.1:4000`; `MERCURY_GATEWAY_URL` overrides.

**`mercury down` refuses.** Sandboxes are running. `mercury kill` them or `mercury down --force`.

**Virtual keys: "could not mint a virtual key".** The gateway has no database. Check `LITELLM_DB_PASSWORD` is set and `mercury logs gateway-db` is healthy; on Kubernetes check `DATABASE_URL` or the bundled Postgres.

## Sandboxes

**The sandbox exits immediately with a git authentication error.** The token cannot reach that repository. For a PAT, check its repository scope and contents write. For a GitHub App, check the App is installed on that repository; `mercury doctor` shows which mode is active.

**It clones but never pushes, no error.** `SANDBOX_GIT_TOKEN` is empty and no App is configured. The log says so at the top.

**opencode hit the time limit.** Whatever it managed is pushed and marked in the log. Raise `--timeout`, or split the task.

**Every model call fails.** No provider key, or the key does not match the provider the chosen model routes to. `cheap-default` needs `OPENROUTER_API_KEY`, `claude-sonnet` needs `ANTHROPIC_API_KEY`.

**`mercury sandbox <url>` with no task fails on Kubernetes.** The interactive TUI is Docker-only. Give it a task, or `mercury exec` into a running Job.

**A sandbox has been running for a day.** `mercury doctor` warns about these. `mercury logs <name>` to see what it is doing, `mercury kill <name>` if nothing.

## Home Assistant

**The log says it cannot reach the host's Docker.** The `docker_api` grant is missing: the add-on was installed from a fork that dropped it, or the Supervisor does not expose the socket. Nothing in the add-on works without it.

**The page says `mercuryd: 401`.** You reached the add-on by its mapped port rather than through ingress, without `api_token`. Use the sidebar panel or set a token.

**The gateway is not reachable from another machine.** It is published on the host's loopback by default. Turn on `expose_gateway`.

## Kubernetes

**Jobs stay Pending.** `kubectl describe job/<name>`: usually an image pull (set `imagePullSecrets`) or resource requests the nodes cannot meet (`sandbox.memoryRequest`, `cpusRequest`).

**The sandbox cannot clone.** The NetworkPolicy allows egress to public addresses on 443 and 22 only. A git server on a private range needs `sandbox.networkPolicy.extraEgressCidrs`, and a non-standard port needs `egressPorts`.

**The controller says it cannot create jobs.** RBAC. The chart's Role binds to the controller's ServiceAccount; if you disabled `rbac.create`, bind an equivalent yourself.
