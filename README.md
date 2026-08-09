# agent-stack

Self-hosted agent setup for a Mac mini (or any Docker host):

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
