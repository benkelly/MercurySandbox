---
title: Locking down credentials
weight: 2
description: Give each sandbox its own budgeted model key and a one-hour token for one repository.
---

A sandbox runs model output, so it should hold as little as possible, for as short a time as possible. Out of the box it holds the gateway master key and your git token, which is simple and is also the largest blast radius on offer. Two optional features shrink it. Both are minted by the controller, which keeps the long-lived secrets and hands out only the short-lived result; both fall back to the old behaviour when not configured.

| | Without | With |
|---|---|---|
| A compromised sandbox can spend | your whole account, on any model, forever | up to `SANDBOX_BUDGET_USD` on one model, until the key expires |
| A compromised sandbox can push to | every repository the PAT covers, until you rotate it | one repository, for one hour |

## Virtual keys

LiteLLM can mint keys limited to a model list, a budget and a duration. It needs a database for that, so:

**Compose (laptop, server):**

```bash
# .env
MERCURY_VIRTUAL_KEYS=1
LITELLM_DB_PASSWORD=$(openssl rand -hex 16)
SANDBOX_BUDGET_USD=5        # per sandbox, optional
SANDBOX_KEY_TTL=24h         # optional
```

`mercury up` then layers `compose.keys.yaml` on: a Postgres on its own internal network that only the gateway can reach. `mercury doctor` reports "virtual keys on".

**Home Assistant:** turn on `virtual_keys` and optionally set `sandbox_budget_usd`. The add-on generates the database password.

**Kubernetes:** `gateway.virtualKeys.enabled=true` with either `bundledPostgres.enabled=true` or `secrets.databaseUrl`.

From then on each `mercury sandbox` creates a key with `key_alias` set to the sandbox name and metadata naming the repo and branch, so LiteLLM's spend logs tell you which task cost what. A foreground run revokes its key when it ends; detached runs let it expire. `--budget` overrides the cap for one sandbox.

## GitHub App tokens

A GitHub App installed on exactly the repositories agents may touch lets the controller mint an installation token per sandbox: that one repository, `contents: write`, one hour, plus `pull_requests: write` only when `--open-pr` is used.

1. Create an App under your account or organisation (**Settings → Developer settings → GitHub Apps**). Repository permissions: **Contents: read and write**, and **Pull requests: read and write** if you want `--open-pr`. No webhook, no other permissions.
2. Install it on the repositories agents may push to. The installation ID is the number at the end of the installation's URL.
3. Generate a private key and download the `.pem`.

Then, per environment:

```bash
# .env, compose
GITHUB_APP_ID=12345
GITHUB_APP_INSTALLATION_ID=67890
GITHUB_APP_PRIVATE_KEY_FILE=/home/you/mercury-app.pem
```

Home Assistant: `github_app_id`, `github_app_installation_id`, and the key saved as `/addon_configs/<slug>/github-app.pem`. Kubernetes: `sandbox.githubApp.appId`, `installationId`, and `secrets.githubAppPrivateKey`.

`SANDBOX_GIT_TOKEN` stays useful as the fallback for repositories off GitHub. Either way the token reaches git through a credential helper that reads it from the environment at call time, so it is never written into a URL, `.git/config` or the process list.

## What a sandbox never gets

No provider keys, no Docker socket, no cluster token (`automountServiceAccountToken: false`), no host paths, no capabilities, no writable root filesystem. If you find yourself wanting to add one of these for a task, that task belongs on the server, not in a sandbox.
