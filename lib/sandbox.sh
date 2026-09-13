#!/usr/bin/env bash
# Spawn a throwaway opencode sandbox. This file decides *what* a sandbox
# gets: its name, image, branch, caps, the narrowest credentials that will
# do, its rules and context. The backend (lib/backend-docker.sh or
# lib/backend-kube.sh) decides *how* that runs. The container side is
# sandbox/entrypoint.sh, driven entirely by the environment set here.
#
# The CLI, mercuryd and the Home Assistant add-on all come through here.

sandbox_usage() {
  cat <<'USAGE'
usage: mercury sandbox [options] <git-url> [task] [model]

  No task:        interactive opencode TUI in the sandbox (docker backend, needs a terminal)
  With a task:    opencode runs it, commits, pushes a branch, container exits

options:
  -d, --detach          run in the background, print the sandbox name
      --model <name>    gateway model name (default: SANDBOX_DEFAULT_MODEL or cheap-default)
      --branch <name>   work branch to push (default: agent/<timestamp>)
      --base <branch>   branch to clone (default: the remote's default branch)
      --context <text>  extra context appended to the task (file contents with --context @path)
      --timeout <secs>  kill opencode after this long (default: SANDBOX_TIMEOUT or 3600)
      --budget <usd>    spend cap for this sandbox's gateway key (virtual keys only)
      --open-pr         open a pull request after pushing (GitHub, needs a token that may)
      --no-push         commit but never push, for a dry run
      --shell           drop into bash in a fresh sandbox instead of opencode (docker backend)
  -h, --help            this help

credentials handed to the sandbox, narrowest available:
  gateway   a virtual key for this one model, budget and lifetime when
            MERCURY_VIRTUAL_KEYS=1, else the master key
  git       a one-hour GitHub App token for this one repository when
            GITHUB_APP_* are set, else SANDBOX_GIT_TOKEN
USAGE
}

sandbox_run() {
  local detach=0 shell=0 push=1 open_pr=0 model="" branch="" base="" context="" timeout="" budget=""
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -d | --detach) detach=1 ;;
      --shell) shell=1 ;;
      --no-push) push=0 ;;
      --open-pr) open_pr=1 ;;
      --model) model="${2:?--model needs a value}"; shift ;;
      --branch) branch="${2:?--branch needs a value}"; shift ;;
      --base) base="${2:?--base needs a value}"; shift ;;
      --context) context="${2:?--context needs a value}"; shift ;;
      --timeout) timeout="${2:?--timeout needs a value}"; shift ;;
      --budget) budget="${2:?--budget needs a value}"; shift ;;
      -h | --help) sandbox_usage; return 0 ;;
      --) shift; positional+=("$@"); break ;;
      -*) die "sandbox: unknown option '$1' (mercury sandbox --help)" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  local repo="${positional[0]:-}" task="${positional[1]:-}"
  [ -n "$model" ] || model="${positional[2]:-${SANDBOX_DEFAULT_MODEL:-cheap-default}}"
  if [ -z "$repo" ]; then
    sandbox_usage >&2
    return 1
  fi
  case "$repo" in
    https://* | http://* | ssh://* | git@*) ;;
    *) die "sandbox: repo must be an https://, ssh:// or git@ URL" ;;
  esac
  [ "$detach" -eq 1 ] && [ -z "$task" ] && [ "$shell" -eq 0 ] &&
    die "sandbox: --detach needs a task, an interactive TUI cannot run in the background"
  if [ "${context:0:1}" = "@" ]; then
    context="$(cat "${context:1}")" || die "sandbox: cannot read context file ${context:1}"
  fi
  [ -n "$timeout" ] || timeout="${SANDBOX_TIMEOUT:-3600}"
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "sandbox: --timeout must be a number of seconds"

  load_env
  [ -n "${LITELLM_MASTER_KEY:-}" ] || die "LITELLM_MASTER_KEY not set (is .env filled in?)"

  local stamp suffix
  stamp="$(date +%Y%m%d-%H%M%S)"
  suffix="$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"

  # ---- the spec the backend runs ------------------------------------------
  SPEC_NAME="mercury-${stamp}-${suffix}"
  SPEC_IMAGE="$(sandbox_image)"
  SPEC_REPO="$repo"
  SPEC_TASK="$task"
  SPEC_MODEL="$model"
  SPEC_BRANCH="${branch:-agent/${stamp}-${suffix}}"
  SPEC_MEMORY="${SANDBOX_MEMORY:-2g}"
  SPEC_CPUS="${SANDBOX_CPUS:-2}"
  SPEC_TIMEOUT="$timeout"
  SPEC_DETACH="$detach"
  if [ "$shell" -eq 1 ]; then SPEC_MODE=shell
  elif [ -z "$task" ]; then SPEC_MODE=tui
  else SPEC_MODE=task; fi

  # Credentials: mint the narrowest available. Both calls fall back to the
  # long-lived secret when nothing narrower is configured.
  [ -n "$budget" ] && export SANDBOX_BUDGET_USD="$budget"
  SPEC_GATEWAY_KEY="$(creds_gateway_key "$SPEC_NAME" "$SPEC_MODEL" "$SPEC_REPO" "$SPEC_BRANCH")"
  local git_token
  git_token="$(creds_git_token "$SPEC_REPO" "$open_pr")"
  if [ "$open_pr" -eq 1 ] && [ -z "$git_token" ]; then
    die "sandbox: --open-pr needs a git token (SANDBOX_GIT_TOKEN or a GitHub App)"
  fi

  # Rules the agent reads as global instructions; a file of your own wins.
  local rules=""
  if [ -n "${SANDBOX_RULES_FILE:-}" ]; then
    rules="$(cat "$SANDBOX_RULES_FILE")" || die "sandbox: cannot read SANDBOX_RULES_FILE=$SANDBOX_RULES_FILE"
  fi

  SPEC_ENV=(
    "OPENAI_BASE_URL=${SANDBOX_GATEWAY_URL:-http://gateway:4000/v1}"
    "MERCURY_REPO_URL=$SPEC_REPO"
    "MERCURY_TASK=$SPEC_TASK"
    "MERCURY_CONTEXT=$context"
    "MERCURY_RULES=$rules"
    "MERCURY_MODEL=$SPEC_MODEL"
    "MERCURY_BRANCH=$SPEC_BRANCH"
    "MERCURY_BASE_BRANCH=$base"
    "MERCURY_PUSH=$push"
    "MERCURY_OPEN_PR=$open_pr"
    "MERCURY_TIMEOUT=$SPEC_TIMEOUT"
    "GITHUB_API_URL=${GITHUB_API_URL:-https://api.github.com}"
    "GIT_AUTHOR_NAME=${SANDBOX_GIT_NAME:-mercury-sandbox}"
    "GIT_AUTHOR_EMAIL=${SANDBOX_GIT_EMAIL:-agents@example.com}"
    "GIT_COMMITTER_NAME=${SANDBOX_GIT_NAME:-mercury-sandbox}"
    "GIT_COMMITTER_EMAIL=${SANDBOX_GIT_EMAIL:-agents@example.com}"
  )
  SPEC_SECRET_ENV=(
    "OPENAI_API_KEY=$SPEC_GATEWAY_KEY"
    "MERCURY_GIT_TOKEN=$git_token"
  )
  export SPEC_NAME SPEC_IMAGE SPEC_REPO SPEC_TASK SPEC_MODEL SPEC_BRANCH SPEC_MEMORY SPEC_CPUS \
    SPEC_TIMEOUT SPEC_DETACH SPEC_MODE SPEC_GATEWAY_KEY SPEC_ENV SPEC_SECRET_ENV

  backend_spawn
}
