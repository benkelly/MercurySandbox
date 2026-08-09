#!/usr/bin/env bash
# Spawn a throwaway opencode sandbox against one repo.
#
#   ./sandbox/run-sandbox.sh <git-url> "<task prompt>" [model-name]
#
# The container: clones the repo, runs opencode non-interactively with the
# task, pushes a work branch, then self-destructs (--rm). Interactive instead?
# Run with just the git-url and you'll be dropped into the opencode TUI.

set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && source .env && set +a

REPO_URL="${1:?usage: run-sandbox.sh <git-url> [task] [model]}"
TASK="${2:-}"
MODEL="${3:-cheap-default}"
BRANCH="agent/$(date +%Y%m%d-%H%M%S)"

# Inject the PAT into the clone URL only inside the container's env, scoped
# token, branch push only.
AUTHED_URL="${REPO_URL/https:\/\//https://x-access-token:${SANDBOX_GIT_TOKEN}@}"

DOCKER_ARGS=(
  --rm
  --network agentnet
  --read-only
  --tmpfs /tmp:rw,size=256m
  --tmpfs /work:rw,exec,size=2g,uid=1000
  --tmpfs /home/agent:rw,exec,size=512m,uid=1000
  --memory 2g --cpus 2
  --cap-drop ALL
  --security-opt no-new-privileges
  -e OPENAI_BASE_URL="http://gateway:4000/v1"
  -e OPENAI_API_KEY="${LITELLM_MASTER_KEY}"
  -e GIT_AUTHOR_NAME="${SANDBOX_GIT_NAME}"
  -e GIT_AUTHOR_EMAIL="${SANDBOX_GIT_EMAIL}"
  -e GIT_COMMITTER_NAME="${SANDBOX_GIT_NAME}"
  -e GIT_COMMITTER_EMAIL="${SANDBOX_GIT_EMAIL}"
)

SETUP="git clone --depth 1 '${AUTHED_URL}' repo && cd repo && git checkout -b '${BRANCH}'"

if [ -z "${TASK}" ]; then
  # Interactive: you drive the TUI, container still evaporates on exit
  exec docker run -it "${DOCKER_ARGS[@]}" agent-sandbox:latest \
    -c "${SETUP} && opencode"
fi

# Non-interactive: run the task, commit and push whatever changed
exec docker run "${DOCKER_ARGS[@]}" agent-sandbox:latest -c "
  ${SETUP} &&
  opencode run --model \"openai/${MODEL}\" \"${TASK}\" &&
  git add -A &&
  git diff --cached --quiet || git commit -m 'agent: ${TASK}' &&
  git push origin '${BRANCH}' &&
  echo '--- pushed ${BRANCH}, review and merge when happy ---'
"
