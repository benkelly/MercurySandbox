# MercurySandbox

> A safe playground for autonomous coding agents.

[![CI](https://github.com/benkelly/MercurySandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/benkelly/MercurySandbox/actions/workflows/ci.yml)

An open-source sandbox for running Hermes-powered coding agents securely,
self-hosted on a Mac mini (or any Docker host):

- **LiteLLM gateway** (Docker, via Terraform), one OpenAI-compatible endpoint, all API keys live here
- **opencode sandbox image** (Docker), throwaway containers for coding tasks
- **Hermes agent** (native on macOS), persistent brain, uses its Docker backend for isolation
- **hermes-webui** (native), browser and mobile UI for Hermes
- **opencode-manager** (Docker, its own compose), mobile-first PWA for opencode sessions

The model APIs do the heavy lifting, so an M4 mini handles all of this comfortably.

## Prerequisites

- Docker Desktop (or OrbStack, which is lighter on macOS)
- Terraform >= 1.6 (`brew install terraform`)
- git, curl

## Setup order

Each step works on its own, so stop wherever you like and test.

### 1. Gateway + sandbox image (Terraform)

```bash
cp .env.example .env        # add your real API keys
cd terraform
terraform init
terraform apply
```

This creates a Docker network, builds the sandbox image, and starts LiteLLM
on http://localhost:4000. Test it:

```bash
curl http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

### 2. Prove the sandbox loop manually

```bash
./sandbox/run-sandbox.sh https://github.com/you/some-repo.git "add a health endpoint"
```

Spawns a throwaway container, clones the repo, runs opencode against the
gateway, pushes a branch, self-destructs. No API keys ever enter the sandbox,
opencode talks to LiteLLM over the Docker network.

### 3. Hermes (native)

```bash
./scripts/install-hermes.sh
```

Then run `hermes setup` and:
- point its model provider at `http://localhost:4000/v1` with your LITELLM_MASTER_KEY
  (OpenAI-compatible endpoint), or configure providers directly if you prefer
- choose the **Docker** terminal backend so Hermes executes shell work inside
  containers rather than on your Mac (see the Hermes docs, backend options are
  local, Docker, SSH and others)
- optionally set up the Telegram gateway (`hermes gateway`) for phone access

Hermes memory lives in `~/.hermes/` as markdown. Back that directory up, it's
the whole brain.

### 4. hermes-webui (native)

```bash
./scripts/install-webui.sh
```

Auto-discovers your `~/.hermes` setup. Manage with `./ctl.sh status|logs|restart`
from the hermes-webui directory.

### 5. opencode-manager (Docker)

```bash
./scripts/install-ocm.sh
```

Opens on http://localhost:5003, first launch prompts you to create an admin
account. Point its AI configuration at the LiteLLM gateway
(`http://host.docker.internal:4000/v1`) so keys stay in one place. Install it
as a PWA on your phone for push notifications when an agent needs an answer.

## The `mercury` CLI

`bin/mercury` wraps the common operations, add `bin/` to your PATH or symlink
it somewhere convenient:

```bash
mercury up            # terraform init + apply: network, gateway, sandbox image
mercury plan          # see what up would change
mercury sandbox https://github.com/you/some-repo.git "add a health endpoint"
mercury models        # list models the gateway exposes
mercury status        # gateway container status
mercury install hermes|webui|ocm
mercury down          # tear it all down
```

## CI/CD

GitHub Actions runs on every push and pull request:

- **ci.yml**: `bash -n` + shellcheck on all scripts, `terraform fmt`/`validate`,
  hadolint on the sandbox Dockerfile, a no-push smoke build of the sandbox
  image, and a `mercury` CLI smoke test
- **release-image.yml**: on pushes to `main` that touch `sandbox/`, builds the
  sandbox image for amd64 and arm64 and publishes it to GHCR as
  `ghcr.io/benkelly/mercury-sandbox`

To use the published image instead of building locally:

```bash
docker pull ghcr.io/benkelly/mercury-sandbox:latest
docker tag ghcr.io/benkelly/mercury-sandbox:latest agent-sandbox:latest
```

## Remote access

Don't port forward. Install Tailscale on the mini and your phone/laptop, then
reach every UI over the tailnet:

- hermes-webui: `http://<mini-tailscale-ip>:<port>`
- opencode-manager: `http://<mini-tailscale-ip>:5003`
- Telegram works from anywhere with no extra setup

## Security model

- Sandboxes: `--rm`, no credentials, read-only root, tmpfs workdir, CPU/mem
  caps, isolated network with the gateway as the only useful egress
- Git is the only write path out, use a fine-grained PAT or deploy key scoped
  to the one repo, agents push branches, you merge
- All model API keys live in LiteLLM only
- Later, on the UDM-SE: put the mini on its own VLAN with an egress allowlist

## Moving off the mini later

The Terraform is provider-agnostic Docker, so pointing it at a Linux host is a
one-line change to the provider block (ssh:// docker host), and Hermes installs
the same way on any Linux box. `~/.hermes` moves with a copy.
