---
title: Releasing
weight: 2
description: Conventional commits in, a release PR out, images and chart versions that agree.
---

Releases are driven by [release-please](https://github.com/googleapis/release-please). You never edit `VERSION` or `CHANGELOG.md` by hand.

## The flow

1. Commits on `main` follow [Conventional Commits](https://www.conventionalcommits.org/): `feat: …`, `fix: …`, `docs: …`, `feat!: …` for a breaking change. Squash-merge pull requests with a conventional title.
2. release-please keeps a **release PR** open on `main`. It bumps `VERSION`, the chart's `version` and `appVersion`, and prepends to `CHANGELOG.md` from the commit messages. `feat` bumps the minor, `fix` the patch, `!` the major.
3. Merging the release PR creates the tag `vX.Y.Z` and a GitHub release, then calls the publish workflow, which pushes `ghcr.io/benkelly/mercury:X.Y.Z` and `ghcr.io/benkelly/mercury-sandbox:X.Y.Z` (multi-arch) plus `latest`, and the Helm chart to `oci://ghcr.io/benkelly/charts/mercury:X.Y.Z`.
4. In the [ha-addons](https://github.com/benkelly/ha-addons) repository, a daily workflow notices the new release and opens a PR bumping the add-on's pinned image tag, version and changelog. Merge it and the add-on updates.

Pushes to `main` that are not releases publish `edge` and `sha-<commit>` image tags for people tracking the tip; the chart is published for releases only.

The first release is no different: the manifest starts at `0.0.0`, so the first `feat:` on `main` produces a release PR for `0.1.0`.

## By hand

Tagging manually still works: `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z` runs the same publish workflow. The workflow refuses a tag that does not match `VERSION`.

## What is pinned where

| Thing | Pinned in | Bumped by |
|---|---|---|
| LiteLLM | `gateway/Dockerfile`, `charts/mercury/values.yaml` | a `deps:` commit |
| cloudflared | `compose.yaml` | a `deps:` commit |
| Alpine, node | `Dockerfile`, `sandbox/Dockerfile` | a `deps:` commit |
| opencode | unpinned on purpose (`OPENCODE_VERSION` build arg) | every image build |
| The chart's versions | `charts/mercury/Chart.yaml` | release-please, from `VERSION` |
| The add-on's base image | `mercury-sandbox/Dockerfile` in ha-addons | the ha-addons update workflow |

CI checks that the chart's `version` and `appVersion` equal `VERSION`, so a hand edit that drifts fails before it merges.
