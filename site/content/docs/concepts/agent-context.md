---
title: Agent context and control
weight: 3
description: What the agent is told, how to add per-task context, and how a run is bounded.
---

An agent with no idea where it is wastes its budget discovering the rules. Every sandbox gets three layers of context, cheapest first.

## 1. Rules

opencode reads a global `AGENTS.md` before anything else. The sandbox image ships one at `/etc/mercury/AGENTS.md` ([source](https://github.com/benkelly/MercurySandbox/blob/main/sandbox/AGENTS.md)) that explains the harness:

- the branch already exists and the harness commits and pushes, so do not;
- there is a time limit and a spending cap, so prefer a complete smaller change;
- read the repository's own `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md` and `README.md` first and let them win;
- run the tests if they are quick, never disable them to get green;
- finish with a summary a reviewer can read.

Replace it with your own: `SANDBOX_RULES_FILE=/path/to/AGENTS.md` in `.env`, `sandbox.rules` in the chart, or an `AGENTS.md` in the add-on's config folder. The file is written to the agent's home, never into the repository, so it is never committed.

## 2. The repository's instructions

The rules point the agent at the repository's own instruction files. If a project you send agents to has none, adding an `AGENTS.md` with how to build and test it is the single highest-leverage thing you can do for result quality.

## 3. Per-task context

`--context` (or the context box on the page, or `context` in the API) is appended to the prompt under a `## Context` heading. Use it for links, constraints, where to look, how to test, and what not to touch. Keep the task itself to one sentence that says what "done" means:

```bash
mercury sandbox --context @notes.md https://github.com/you/api.git \
  "Add rate limiting to POST /login: 5 attempts per minute per IP, return 429 with Retry-After"
```

## Bounding a run

| Control | Default | What happens |
|---|---|---|
| `--timeout` / `SANDBOX_TIMEOUT` | 3600 s | opencode is stopped; whatever it managed is still committed and pushed, marked as cut off in the log |
| `--budget` / `SANDBOX_BUDGET_USD` | 5 | with virtual keys on, the gateway refuses calls past this |
| `SANDBOX_MEMORY`, `SANDBOX_CPUS` | 2g, 2 | container or Job limits |
| `--no-push` | off | commit only, for trying a prompt without touching the remote |
| `--open-pr` | off | open the pull request after pushing, with the task as its body |

On Kubernetes the Job also gets `activeDeadlineSeconds` of timeout plus ten minutes, so a stuck clone or push cannot hold a pod forever.

## Writing tasks that work

- One task, one outcome. "Add X with a test" beats "improve the API".
- Say how to verify. "`make test` must pass" turns a guess into a check.
- Name the files if you know them. Discovery is the expensive part.
- Pick the model for the job: `cheap-default` for grunt work, `claude-sonnet` when it has to think.
- Read the summary at the end of the log before the diff. The agent was asked to tell you what it verified and what to look at.
