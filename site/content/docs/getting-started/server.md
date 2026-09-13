---
title: Server
weight: 2
description: Always on, reached privately over Tailscale, driven from your laptop.
---

The server shape is the laptop shape plus three things: it never sleeps, you reach it over Tailscale rather than exposing anything, and it is where Hermes lives so its memory is on a disk you back up.

## Set up the host

1. Install Docker with the compose plugin and Tailscale. Join the tailnet with a tag so ACLs can single it out:

   ```bash
   tailscale up --advertise-tags=tag:agent-host --ssh
   ```

2. Clone and configure exactly as on a [laptop](/docs/getting-started/laptop/): `cp .env.example .env`, fill it in, `./bin/mercury up`, `./bin/mercury doctor`.

3. Leave the ports on loopback (the default). The gateway is on `127.0.0.1:4000` and the page on `127.0.0.1:5004`; both are reached through Tailscale, never the LAN.

The compose services restart with Docker (`restart: unless-stopped`), so a reboot brings the gateway and controller back without you.

## Drive it from your laptop

Every `mercury` command runs remotely over SSH:

```bash
export MERCURY_HOST=you@agent-host       # or: mercury -H you@agent-host <cmd>
mercury status
mercury sandbox https://github.com/you/repo.git "…"
mercury logs mercury-20260913-011148-75b9
```

This needs the repository checked out on the server at `~/MercurySandbox` (or set `MERCURY_REMOTE_DIR`). Interactive commands (the TUI, `exec`) work because the wrapper allocates a terminal.

For the page, forward or use Tailscale Serve:

```bash
ssh -L 5004:127.0.0.1:5004 you@agent-host       # then http://127.0.0.1:5004
tailscale serve --bg 5004                        # or: https://agent-host.<tailnet>.ts.net
```

## Lock the tailnet down

A sample ACL is in [`docs/tailscale-acl.example.json`](https://github.com/benkelly/MercurySandbox/blob/main/docs/tailscale-acl.example.json): personal devices may reach only the stack's ports on `tag:agent-host`, and nothing grants the agent host access to anything else on the tailnet. Paste it into the admin console and adjust the ports.

## Hermes on the server

Hermes runs natively, not in a container, because `~/.hermes/` is its entire memory and you want that on a filesystem you back up:

```bash
./bin/mercury install hermes    # official installer, then: hermes setup
./bin/mercury install webui     # browser and mobile UI
```

Point Hermes at `http://127.0.0.1:4000/v1` with the master key, choose its Docker terminal backend, and give it `mercury sandbox -d <url> "<task>"` (or the API) as the way to hand off a task-sized job. Details in [Hermes and friends](/docs/operations/hermes/).

## Optional: a Cloudflare Tunnel

To share a UI with someone off your tailnet, put `CLOUDFLARE_TUNNEL_TOKEN` in `.env` and run `mercury up`. The `cloudflared` container lives on its own network and cannot reach the gateway even by mistake. Route only host services you have put a Cloudflare Access policy in front of, and never route to port 4000 or 5004.

## Back up

Two things matter: `.env` (every secret) and `~/.hermes/` (the brain). Everything else is rebuilt by `mercury up`.
