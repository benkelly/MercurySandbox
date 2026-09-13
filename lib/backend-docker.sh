#!/usr/bin/env bash
# Docker backend: sandboxes are `docker run --rm` containers on the daemon
# the controller can see (the host's, through the socket).
#
# Reads the SPEC_* globals that lib/sandbox.sh sets up.

backend_name() { printf 'docker'; }

backend_ok() { docker info >/dev/null 2>&1; }

backend_spawn() {
  # shellcheck disable=SC2054  # commas inside --tmpfs values are mount options
  local args=(
    --rm
    --name "$SPEC_NAME"
    --label mercury.sandbox=1
    --label "mercury.repo=$SPEC_REPO"
    --label "mercury.branch=$SPEC_BRANCH"
    --label "mercury.model=$SPEC_MODEL"
    --label "mercury.task=${SPEC_TASK:0:200}"
    --network "${SANDBOX_NETWORK:-agentnet}"
    --read-only
    --tmpfs /tmp:rw,size=256m
    --tmpfs /work:rw,exec,size="${SANDBOX_WORK_SIZE:-2g}",uid=1000,gid=1000
    --tmpfs /home/agent:rw,exec,size=512m,uid=1000,gid=1000
    --memory "$SPEC_MEMORY"
    --cpus "$SPEC_CPUS"
    --pids-limit 512
    --cap-drop ALL
    --security-opt no-new-privileges
  )
  local kv
  for kv in "${SPEC_ENV[@]}" "${SPEC_SECRET_ENV[@]}"; do
    args+=(-e "$kv")
  done

  case "$SPEC_MODE" in
    shell)
      log "shell in $SPEC_NAME (exit to destroy it)"
      exec docker run -it "${args[@]}" "$SPEC_IMAGE" bash
      ;;
    tui)
      log "sandbox $SPEC_NAME -> branch $SPEC_BRANCH  (mercury ps | logs | exec | kill)"
      exec docker run -it "${args[@]}" "$SPEC_IMAGE"
      ;;
  esac
  if [ "$SPEC_DETACH" -eq 1 ]; then
    docker run -d "${args[@]}" "$SPEC_IMAGE" >/dev/null
    log "started $SPEC_NAME -> branch $SPEC_BRANCH  (mercury logs $SPEC_NAME | mercury kill $SPEC_NAME)"
    printf '%s\n' "$SPEC_NAME"
    return 0
  fi
  log "sandbox $SPEC_NAME -> branch $SPEC_BRANCH  (mercury ps | logs | exec | kill)"
  local rc=0
  docker run "${args[@]}" "$SPEC_IMAGE" || rc=$?
  # A foreground run is over, so its virtual key can go now instead of at expiry.
  [ -n "${SPEC_GATEWAY_KEY:-}" ] && creds_revoke_gateway_key "$SPEC_GATEWAY_KEY"
  return "$rc"
}

# JSON array of running sandboxes, the same shape for every backend.
backend_list_json() {
  local ids
  ids="$(docker ps -q --filter label=mercury.sandbox)" || return 1
  if [ -z "$ids" ]; then
    printf '[]\n'
    return 0
  fi
  # shellcheck disable=SC2086  # ids are whitespace separated on purpose
  docker inspect $ids | jq '[.[] | {
      name: (.Name | ltrimstr("/")),
      status: .State.Status,
      started: .State.StartedAt,
      repo: (.Config.Labels["mercury.repo"] // ""),
      branch: (.Config.Labels["mercury.branch"] // ""),
      model: (.Config.Labels["mercury.model"] // ""),
      task: (.Config.Labels["mercury.task"] // ""),
      backend: "docker"
    }] | sort_by(.started) | reverse'
}

backend_ps() {
  docker ps --filter label=mercury.sandbox \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Label "mercury.branch"}}\t{{.Label "mercury.repo"}}'
}

# backend_logs <name> <tail> <follow 0|1>
backend_logs() {
  local args=(--tail "$2")
  [ "$3" = "1" ] && args+=(-f)
  docker logs "${args[@]}" "$1"
}

backend_kill() { docker stop -t 10 "$1"; }

backend_exec() {
  local name="$1"
  shift
  docker exec -it "$name" "$@"
}
