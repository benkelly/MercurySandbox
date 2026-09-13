---
title: Getting started
weight: 1
---

Four ways to run the same stack. Pick the one that matches where your Docker (or cluster) lives.

| Where | Best for | Sandboxes run as | Guide |
|---|---|---|---|
| Laptop | trying it, day-to-day use from one machine | containers on Docker Desktop or OrbStack | [Laptop](/docs/getting-started/laptop/) |
| Server | always-on, Hermes with memory, reached over Tailscale | containers on the server's Docker | [Server](/docs/getting-started/server/) |
| Home Assistant | you already run HAOS and want the page in the sidebar | containers on the HA host's Docker | [Home Assistant](/docs/getting-started/home-assistant/) |
| Kubernetes | a cluster you operate, several people | Jobs with a NetworkPolicy | [Kubernetes](/docs/getting-started/kubernetes/) |

Whichever you choose you will need:

- a model provider key: Anthropic, OpenRouter or OpenAI, at least one;
- a way for sandboxes to push: a fine-grained GitHub token scoped to the repositories agents may touch, or better a [GitHub App](/docs/concepts/credentials/);
- a repository to point the first sandbox at.
