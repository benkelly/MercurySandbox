---
title: Documentation
---

MercurySandbox runs a persistent [Hermes agent](https://github.com/NousResearch/hermes-agent) that remembers everything, and hands the coding work to [opencode](https://opencode.ai) in throwaway containers. Model API keys live in one gateway, sandboxes hold as little as possible for as short a time as possible, and the only way work leaves a sandbox is a git branch you review.

| Start here | If you want to |
|---|---|
| [Getting started](/docs/getting-started/) | run it, on a laptop, a server, Home Assistant or Kubernetes |
| [Architecture](/docs/concepts/architecture/) | understand the pieces and the trust boundaries |
| [Locking down credentials](/docs/concepts/credentials/) | give each sandbox its own budgeted key and one-hour git token |
| [Reference](/docs/reference/) | look up a command, an endpoint or a variable |
| [Operations](/docs/operations/) | connect Hermes, cut a release, fix something |
