---
title: The sandbox contract
weight: 4
description: What the controller hands a sandbox, and what the sandbox does with it.
---

A sandbox is the image `ghcr.io/benkelly/mercury-sandbox` (or a local build of `sandbox/`) run with a set of environment variables. Anything that can set env and run a container can spawn one: the CLI, mercuryd, the add-on, a Kubernetes Job, Hermes, a cron job.

## Environment

| Variable | Meaning |
|---|---|
| `MERCURY_REPO_URL` | Repository to clone. Required. |
| `MERCURY_TASK` | Prompt for `opencode run`. Empty means the interactive TUI. |
| `MERCURY_CONTEXT` | Appended to the prompt under a `## Context` heading. |
| `MERCURY_RULES` | Global instructions; empty uses `/etc/mercury/AGENTS.md` from the image. |
| `MERCURY_MODEL` | A gateway `model_name`. |
| `MERCURY_BRANCH` | Branch to create and push. |
| `MERCURY_BASE_BRANCH` | Branch to clone instead of the remote default. |
| `MERCURY_TIMEOUT` | Seconds before opencode is stopped. |
| `MERCURY_PUSH` | `0` commits without pushing. |
| `MERCURY_OPEN_PR` | `1` opens a GitHub pull request after pushing. |
| `MERCURY_GIT_TOKEN` | Token for https remotes, served through a credential helper. |
| `OPENAI_BASE_URL`, `OPENAI_API_KEY` | The gateway, in the form opencode expects. |
| `GIT_AUTHOR_*`, `GIT_COMMITTER_*` | Commit identity. |

Any command-line arguments make the entrypoint run those instead (`--shell` runs `bash`).

## What the entrypoint does

1. Installs the credential helper (the token is read from the environment at call time and never written down).
2. Writes the rules to `~/.config/opencode/AGENTS.md`, outside the repository.
3. Clones with `--depth 1`, creates the branch.
4. Runs `opencode run --model openai/<model>` under `timeout`, with the task and context as the prompt.
5. `git add -A`; if nothing changed, exits. Otherwise commits with the task as the subject and body.
6. Pushes the branch, then opens a pull request if asked.
7. Exits with opencode's status, so a cut-off or failed run is visible in `docker ps -a` or the Job status while its branch is still there to review.

## Hardening, per backend

| | Docker | Kubernetes |
|---|---|---|
| User | uid 1000 `agent` | `runAsNonRoot`, uid/gid 1000 |
| Root filesystem | `--read-only` | `readOnlyRootFilesystem` |
| Writable paths | tmpfs `/work`, `/home/agent`, `/tmp` with sizes | memory-backed `emptyDir`s with size limits |
| Capabilities | `--cap-drop ALL`, `no-new-privileges` | `drop: [ALL]`, `allowPrivilegeEscalation: false`, `RuntimeDefault` seccomp |
| Limits | `--memory`, `--cpus`, `--pids-limit 512` | resource limits and requests, `activeDeadlineSeconds` |
| Network | `agentnet` only | NetworkPolicy: gateway, DNS, public 443/22 |
| Lifetime | `--rm` | `backoffLimit: 0`, `ttlSecondsAfterFinished` |
| Secrets | env | a Secret per sandbox, owned by the Job |
| Identity | labels `mercury.sandbox`, `mercury.repo`, `mercury.branch`, `mercury.model`, `mercury.task` | the same as labels and annotations |

There is no database anywhere: `mercury ps`, `doctor` and the page read the labels.
