# MercurySandbox

> A safe playground for autonomous coding agents.

[![CI](https://github.com/benkelly/MercurySandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/benkelly/MercurySandbox/actions/workflows/ci.yml)

An open-source sandbox for running Hermes-powered coding agents securely,
self-hosted on any Docker host:

- **LiteLLM gateway** (Docker, via Terraform), one OpenAI-compatible endpoint, all API keys live here
- **opencode sandbox image** (Docker), throwaway containers for coding tasks
- **Hermes agent** (native on macOS), persistent brain, uses its Docker backend for isolation
- **hermes-webui** (native), browser and mobile UI for Hermes
- **opencode-manager** (Docker, its own compose), mobile-first PWA for opencode sessions

The model APIs do the heavy lifting, so a modest machine handles all of this comfortably.

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
  containers rather than on the host (see the Hermes docs, backend options are
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
mercury ps            # list running sandboxes
mercury logs <name>   # follow a sandbox's output
mercury exec <name>   # shell into a running sandbox
mercury kill <name>   # stop one early (it self-deletes)
mercury models        # list models the gateway exposes
mercury status        # gateway container status
mercury install hermes|webui|ocm
mercury down          # tear it all down (refuses while sandboxes run, --force overrides)
```

Every command also works against a remote Docker host over SSH, so from a
laptop on the tailnet:

```bash
export MERCURY_HOST=you@<host-tailscale-name>   # or -H per command
mercury ps
mercury sandbox https://github.com/you/some-repo.git "fix the flaky test"
mercury exec mercury-20260809-120000            # drop into that sandbox
```

This SSHes in and runs the repo's own `mercury` there, so the interactive
sandbox TUI and `exec` work too. Set `MERCURY_REMOTE_DIR` if the repo lives
somewhere other than `~/MercurySandbox` on the remote.

## CI/CD

GitHub Actions runs on every push and pull request:

- **ci.yml**: `bash -n` + shellcheck on all scripts, `terraform fmt`/`validate`,
  hadolint on the sandbox Dockerfile, a no-push smoke build of the sandbox
  image, and a `mercury` CLI smoke test
- **release-image.yml**: on pushes to `main` that touch `sandbox/`, builds the
  sandbox image for amd64 and arm64 and publishes it to GHCR as
  `ghcr.io/benkelly/mercury-sandbox`

To run sandboxes from the published image instead of the local Terraform
build, set `SANDBOX_IMAGE` (in `.env` or the environment):

```bash
SANDBOX_IMAGE=ghcr.io/benkelly/mercury-sandbox:latest ./sandbox/run-sandbox.sh ...
```

## Remote access

Don't port forward. Install Tailscale on the Docker host and your phone/laptop,
then reach every UI over the tailnet:

- hermes-webui: `http://<host-tailscale-ip>:<port>`
- opencode-manager: `http://<host-tailscale-ip>:5003`
- Telegram works from anywhere with no extra setup
- the `mercury` CLI: `MERCURY_HOST=you@<host> mercury ps` (SSH over the tailnet)

### Cloudflare Tunnel (optional)

Prefer Cloudflare, or want a stable public hostname? Create a tunnel in the
Zero Trust dashboard (Networks -> Tunnels), put its token in `.env` as
`CLOUDFLARE_TUNNEL_TOKEN`, and `terraform apply`. A `cloudflared` container
joins the stack and is destroyed with it; leave the token empty and it never
starts.

Route public hostnames to services in the dashboard:

- host services (hermes-webui, opencode-manager): `http://host.docker.internal:<port>`
- anything on agentnet by container name, e.g. `http://gateway:4000`

Put Cloudflare Access in front of every hostname you route — these UIs drive
agents that can push to your repos. Avoid exposing the gateway at all unless
you need to; its master key is the only thing between the internet and your
API spend.

## Security model

- Sandboxes: `--rm`, no credentials, read-only root, tmpfs workdir, CPU/mem
  caps, isolated network with the gateway as the only useful egress
- Git is the only write path out, use a fine-grained PAT or deploy key scoped
  to the one repo, agents push branches, you merge
- All model API keys live in LiteLLM only
- Optionally, put the host on its own VLAN with an egress allowlist at the router

## Moving to another host later

The Terraform is provider-agnostic Docker, so pointing it at a different
machine is a one-line change to the provider block (ssh:// docker host), and
Hermes installs the same way on any Linux box. `~/.hermes` moves with a copy.
