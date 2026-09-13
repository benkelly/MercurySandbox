---
title: Laptop
weight: 1
description: From clone to a pushed branch in about five minutes.
---

## Requirements

Docker with the compose plugin (Docker Desktop, OrbStack or a plain `dockerd`), bash and curl. `jq` makes `mercury models` prettier.

## Install

```bash
git clone https://github.com/benkelly/MercurySandbox.git && cd MercurySandbox
cp .env.example .env
```

Fill in `.env`:

```bash
LITELLM_MASTER_KEY=sk-$(openssl rand -hex 24)   # any string, treat it like a password
ANTHROPIC_API_KEY=sk-ant-...                     # or OPENROUTER_API_KEY, or both
SANDBOX_GIT_TOKEN=github_pat_...                 # fine-grained, only the repos agents may push to
```

Then bring the stack up and check it:

```bash
./bin/mercury up       # builds the gateway image with your routing, the controller, the sandbox image
./bin/mercury doctor   # every line ok, warn or skip; FAIL says what to fix
./bin/mercury models   # the names sandboxes can ask for
```

`mercury up` is idempotent. Run it again after editing `.env` or `gateway/config.yaml`.

## First sandbox

```bash
./bin/mercury sandbox https://github.com/you/some-repo.git "add a /health endpoint with a test"
```

Watch it clone, run opencode, commit and push `agent/<timestamp>`. Review the branch on GitHub, merge or bin it. The container is already gone.

Prefer a page? Open <http://127.0.0.1:5004>: spawn from a form, see running sandboxes, follow logs, stop one.

Useful variations:

```bash
./bin/mercury sandbox -d <url> "task"                  # background, prints the name
./bin/mercury sandbox --model claude-sonnet <url> "…"  # a stronger model
./bin/mercury sandbox --context @notes.md <url> "…"    # extra context from a file
./bin/mercury sandbox --open-pr <url> "…"              # open the PR when it pushes
./bin/mercury sandbox <url>                            # no task: the opencode TUI, interactive
./bin/mercury sandbox --shell <url>                    # bash in a fresh sandbox, to poke around
./bin/mercury ps | logs <name> | exec <name> | kill <name>
```

## Change the models

`gateway/config.yaml` is the only file that names a provider. Add a `model_name`, run `mercury up`, and it appears in `mercury models` and the page. Local Ollama works too: uncomment the example and point it at `host.docker.internal:11434`.

## Next

- [Lock down credentials](/docs/concepts/credentials/): per-sandbox keys and one-hour git tokens.
- [Give the agent context](/docs/concepts/agent-context/): rules, per-task notes, timeouts.
- [Connect Hermes](/docs/operations/hermes/): the always-on brain.
- `mercury down` tears it all down; it refuses while sandboxes run.
