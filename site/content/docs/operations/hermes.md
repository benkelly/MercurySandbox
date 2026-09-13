---
title: Hermes and friends
weight: 1
description: The always-on brain, its web UI, and opencode-manager.
---

MercurySandbox is the hands. The brain is a [Hermes agent](https://github.com/NousResearch/hermes-agent): persistent, with memory in `~/.hermes/` as plain markdown, reachable from your phone over Telegram or the web UI. All three pieces here are optional and independent; the sandbox stack is useful without any of them.

## Hermes

```bash
./bin/mercury install hermes     # the official installer
source ~/.zshrc && hermes setup
```

In setup: provider endpoint `http://127.0.0.1:4000/v1`, API key your `LITELLM_MASTER_KEY`, and the Docker terminal backend so its own shell work runs in containers.

Give Hermes a way to hand off task-sized work. Two options:

- a shell tool that runs `mercury sandbox -d <url> "<task>"` and later `mercury logs --no-follow <name>`;
- the API: `POST /api/sandboxes`, then `GET /api/sandboxes/<name>/logs`.

Either way Hermes decides, the sandbox does, and you review the branch. Hermes never needs the git token or a provider key.

## hermes-webui

```bash
./bin/mercury install webui      # clones and starts it, auto-discovers ~/.hermes
```

Reach it over Tailscale. Its port is in the sample ACL.

## opencode-manager

A PWA for driving opencode sessions from a phone:

```bash
./bin/mercury install ocm        # its own docker compose, on :5003
```

Point its AI configuration at `http://host.docker.internal:4000/v1` with the master key.

## Back up

`~/.hermes/` is the whole brain. `.env` is every secret. Nothing else is precious.
