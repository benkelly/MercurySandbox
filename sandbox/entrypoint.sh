#!/usr/bin/env bash
# Entrypoint of the throwaway sandbox image. Everything a sandbox does lives
# here, driven by environment variables, so whoever spawns it (the mercury
# CLI, mercuryd, the Home Assistant add-on, Hermes) only has to set env and
# run the image.
#
#   MERCURY_REPO_URL     repo to clone (required)
#   MERCURY_TASK         prompt for opencode; empty means interactive TUI
#   MERCURY_MODEL        gateway model name (default cheap-default)
#   MERCURY_BRANCH       branch to create and push (default agent/<timestamp>)
#   MERCURY_BASE_BRANCH  branch to clone instead of the remote default
#   MERCURY_PUSH         0 to commit without pushing
#   MERCURY_GIT_TOKEN    token for https remotes, served through a credential
#                        helper so it is never written to disk or into a URL
#   OPENAI_BASE_URL/OPENAI_API_KEY  the gateway, as opencode expects them
#
# Any arguments mean "run this instead" (mercury sandbox --shell uses bash).
set -euo pipefail

if [ $# -gt 0 ]; then
  exec "$@"
fi

: "${MERCURY_REPO_URL:?MERCURY_REPO_URL is required}"
MODEL="${MERCURY_MODEL:-cheap-default}"
BRANCH="${MERCURY_BRANCH:-agent/$(date +%Y%m%d-%H%M%S)}"
WORK=/work/repo

say() { printf '\n--- %s ---\n' "$*"; }

# Never wait on a password prompt: a missing token should fail, not hang.
export GIT_TERMINAL_PROMPT=0

if [ -n "${MERCURY_GIT_TOKEN:-}" ]; then
  # The helper reads the token from its own environment at call time, so it
  # appears neither in .git/config nor in the process list.
  git config --global credential.helper \
    '!f() { echo "username=x-access-token"; echo "password=${MERCURY_GIT_TOKEN}"; }; f'
fi

say "cloning ${MERCURY_REPO_URL}"
clone_args=(--depth 1)
[ -n "${MERCURY_BASE_BRANCH:-}" ] && clone_args+=(--branch "$MERCURY_BASE_BRANCH")
git clone "${clone_args[@]}" "$MERCURY_REPO_URL" "$WORK"
cd "$WORK"
git checkout -q -b "$BRANCH"

if [ -z "${MERCURY_TASK:-}" ]; then
  say "interactive: opencode on branch ${BRANCH}, push it yourself before you exit"
  exec opencode
fi

say "opencode (${MODEL}): ${MERCURY_TASK}"
opencode run --model "openai/${MODEL}" "$MERCURY_TASK"

git add -A
if git diff --cached --quiet; then
  say "opencode changed nothing, no branch pushed"
  exit 0
fi

# Short subject, full task in the body.
subject="agent: ${MERCURY_TASK}"
if [ "${#subject}" -gt 72 ]; then
  git commit -q -m "${subject:0:69}..." -m "$MERCURY_TASK"
else
  git commit -q -m "$subject"
fi
git --no-pager show --stat --oneline HEAD | head -40

if [ "${MERCURY_PUSH:-1}" = "0" ]; then
  say "MERCURY_PUSH=0, committed on ${BRANCH} but not pushed"
  exit 0
fi

say "pushing ${BRANCH}"
git push -u origin "$BRANCH"
say "pushed ${BRANCH}, review and merge when happy"
