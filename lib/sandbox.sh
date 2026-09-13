#!/usr/bin/env bash
# Spawn a throwaway opencode sandbox. This is the single place that knows how
# a sandbox container is hardened; the CLI, mercuryd and the Home Assistant
# add-on all come through here.
#
# The container itself does the work (clone, branch, run opencode, commit,
# push) via sandbox/entrypoint.sh, driven entirely by environment variables,
# so this file is only about docker run flags.

sandbox_usage() {
  cat <<'USAGE'
usage: mercury sandbox [options] <git-url> [task] [model]

  No task:        interactive opencode TUI in the sandbox (needs a terminal)
  With a task:    opencode runs it, commits, pushes a branch, container exits

options:
  -d, --detach          run in the background, print the container name
      --model <name>    gateway model name (default: SANDBOX_DEFAULT_MODEL or cheap-default)
      --branch <name>   work branch to push (default: agent/<timestamp>)
      --base <branch>   branch to clone (default: the remote's default branch)
      --no-push         commit but never push, for a dry run
      --shell           drop into bash in a fresh sandbox instead of opencode
  -h, --help            this help
USAGE
}

sandbox_run() {
  local detach=0 shell=0 push=1 model="" branch="" base="" repo="" task=""
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -d | --detach) detach=1 ;;
      --shell) shell=1 ;;
      --no-push) push=0 ;;
      --model) model="${2:?--model needs a value}"; shift ;;
      --branch) branch="${2:?--branch needs a value}"; shift ;;
      --base) base="${2:?--base needs a value}"; shift ;;
      -h | --help) sandbox_usage; return 0 ;;
      --) shift; positional+=("$@"); break ;;
      -*) die "sandbox: unknown option '$1' (mercury sandbox --help)" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  repo="${positional[0]:-}"
  task="${positional[1]:-}"
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

  load_env
  [ -n "${LITELLM_MASTER_KEY:-}" ] || die "LITELLM_MASTER_KEY not set (is .env filled in?)"

  local stamp suffix name
  stamp="$(date +%Y%m%d-%H%M%S)"
  suffix="$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
  name="mercury-${stamp}-${suffix}"
  [ -n "$branch" ] || branch="agent/${stamp}-${suffix}"

  # shellcheck disable=SC2054  # commas inside --tmpfs values are mount options
  local args=(
    --rm
    --name "$name"
    --label mercury.sandbox=1
    --label "mercury.repo=$repo"
    --label "mercury.branch=$branch"
    --label "mercury.model=$model"
    --label "mercury.task=${task:0:200}"
    --network "${SANDBOX_NETWORK:-agentnet}"
    --read-only
    --tmpfs /tmp:rw,size=256m
    --tmpfs /work:rw,exec,size="${SANDBOX_WORK_SIZE:-2g}",uid=1000,gid=1000
    --tmpfs /home/agent:rw,exec,size=512m,uid=1000,gid=1000
    --memory "${SANDBOX_MEMORY:-2g}"
    --cpus "${SANDBOX_CPUS:-2}"
    --pids-limit 512
    --cap-drop ALL
    --security-opt no-new-privileges
    -e OPENAI_BASE_URL="${SANDBOX_GATEWAY_URL:-http://gateway:4000/v1}"
    -e OPENAI_API_KEY="$LITELLM_MASTER_KEY"
    -e MERCURY_REPO_URL="$repo"
    -e MERCURY_TASK="$task"
    -e MERCURY_MODEL="$model"
    -e MERCURY_BRANCH="$branch"
    -e MERCURY_BASE_BRANCH="$base"
    -e MERCURY_PUSH="$push"
    -e MERCURY_GIT_TOKEN="${SANDBOX_GIT_TOKEN:-}"
    -e GIT_AUTHOR_NAME="${SANDBOX_GIT_NAME:-mercury-sandbox}"
    -e GIT_AUTHOR_EMAIL="${SANDBOX_GIT_EMAIL:-agents@example.com}"
    -e GIT_COMMITTER_NAME="${SANDBOX_GIT_NAME:-mercury-sandbox}"
    -e GIT_COMMITTER_EMAIL="${SANDBOX_GIT_EMAIL:-agents@example.com}"
  )
  local image
  image="$(sandbox_image)"

  if [ "$shell" -eq 1 ]; then
    log "shell in $name (exit to destroy it)"
    exec docker run -it "${args[@]}" "$image" bash
  fi
  if [ "$detach" -eq 1 ]; then
    docker run -d "${args[@]}" "$image" >/dev/null
    log "started $name -> branch $branch  (mercury logs $name | mercury kill $name)"
    printf '%s\n' "$name"
    return 0
  fi
  log "sandbox $name -> branch $branch  (mercury ps | logs | exec | kill)"
  if [ -z "$task" ]; then
    exec docker run -it "${args[@]}" "$image"
  fi
  exec docker run "${args[@]}" "$image"
}
