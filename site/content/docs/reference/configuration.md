---
title: Configuration
weight: 3
description: Every variable in .env, and what each deployment shape does with it.
---

`.env` is read by `bin/mercury`, passed to compose as its env file, and handed to the controller container. The Home Assistant add-on writes it from its options; the chart sets the same variables on the controller Deployment.

## Required

| Variable | Meaning |
|---|---|
| `LITELLM_MASTER_KEY` | Key clients use to talk to the gateway. Any string; LiteLLM prefers an `sk-` prefix. |
| `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `OPENAI_API_KEY` | Provider keys. Only the gateway sees them. At least one. |

## Sandboxes

| Variable | Default | Meaning |
|---|---|---|
| `SANDBOX_GIT_TOKEN` | | Fallback git token for https remotes. |
| `SANDBOX_GIT_NAME`, `SANDBOX_GIT_EMAIL` | `mercury-sandbox`, `agents@example.com` | Commit identity. |
| `SANDBOX_DEFAULT_MODEL` | `cheap-default` | Model when none is chosen. |
| `SANDBOX_IMAGE` | `mercury-sandbox:local` | Image to run. The default builds `sandbox/` locally on `mercury up`; a `ghcr.io/…` name is pulled instead. |
| `SANDBOX_MEMORY`, `SANDBOX_CPUS` | `2g`, `2` | Per-sandbox caps. |
| `SANDBOX_WORK_SIZE` | `2g` | tmpfs size for `/work`. |
| `SANDBOX_TIMEOUT` | `3600` | Seconds before opencode is stopped. |
| `SANDBOX_RULES_FILE` | | Replaces the agent rules baked into the image. |
| `SANDBOX_NETWORK` | `agentnet` | Docker network sandboxes join. |
| `SANDBOX_GATEWAY_URL` | `http://gateway:4000/v1` | Gateway as seen from a sandbox. |

## Least privilege

| Variable | Meaning |
|---|---|
| `MERCURY_VIRTUAL_KEYS=1` | Mint a per-sandbox gateway key. Layers `compose.keys.yaml` on. |
| `LITELLM_DB_PASSWORD` | Password for the gateway database that virtual keys need. |
| `SANDBOX_BUDGET_USD`, `SANDBOX_KEY_TTL` | `5`, `24h`. Limits on each minted key. |
| `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID` | The App that mints one-hour single-repository tokens. |
| `GITHUB_APP_PRIVATE_KEY_FILE` or `GITHUB_APP_PRIVATE_KEY` | Its private key, as a path or inline PEM. |
| `GITHUB_API_URL`, `GITHUB_HOST` | For GitHub Enterprise. Defaults `https://api.github.com`, `github.com`. |

## Ports and the controller

| Variable | Default | Meaning |
|---|---|---|
| `GATEWAY_BIND`, `GATEWAY_PORT` | `127.0.0.1`, `4000` | Where the gateway is published on the host. |
| `MERCURY_BIND`, `MERCURY_PORT` | `127.0.0.1`, `5004` | Where mercuryd is published. |
| `MERCURY_API_TOKEN` | | Bearer token for the API. Set it if the port leaves loopback. |
| `MERCURY_TRUSTED_PROXY`, `MERCURY_INGRESS_ONLY` | | Set by the add-on for ingress. |
| `MERCURY_GATEWAY_URL` | context-dependent | Gateway as seen by mercuryd and the CLI. |
| `CLOUDFLARE_TUNNEL_TOKEN` | | Turns on the `tunnel` compose profile. |

## Backend

| Variable | Meaning |
|---|---|
| `SANDBOX_BACKEND` | `docker` (default) or `kubernetes`. |
| `KUBE_NAMESPACE` | Namespace for Jobs; defaults to the pod's own. |
| `SANDBOX_SERVICE_ACCOUNT`, `SANDBOX_IMAGE_PULL_SECRET` | Optional, for sandbox pods. |
| `SANDBOX_MEMORY_REQUEST`, `SANDBOX_CPUS_REQUEST`, `SANDBOX_JOB_TTL` | `512m`, `0.25`, `3600`. Kubernetes only. |

## Files

| File | Holds |
|---|---|
| `compose.yaml` | gateway, controller, optional tunnel |
| `compose.keys.yaml` | the gateway database for virtual keys |
| `gateway/config.yaml` | model routing, the only place a provider is named |
| `gateway/Dockerfile` | the pinned LiteLLM release |
| `sandbox/AGENTS.md` | default agent rules |
| `VERSION` | the one version number; the chart and images follow it |
