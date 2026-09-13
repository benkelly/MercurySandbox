#!/usr/bin/env bash
# Long-lived part of the stack: gateway, controller, optional tunnel, and the
# sandbox image. Thin wrappers over docker compose plus the checks that make
# `mercury up` and `mercury down` safe to run without thinking.

# Usage: stack_up [--pull]
#   Builds (or pulls) and starts the compose services, then makes sure the
#   sandbox image exists. MERCURY_SERVICES limits which services start; the
#   Home Assistant add-on sets it to "gateway" because it is the controller.
stack_up() {
  local pull=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --pull) pull=1 ;;
      *) die "up: unknown option '$1'" ;;
    esac
    shift
  done

  require_env_file
  load_env
  [ -n "${LITELLM_MASTER_KEY:-}" ] && [ "$LITELLM_MASTER_KEY" != "sk-local-change-me" ] ||
    die "LITELLM_MASTER_KEY is empty or still the placeholder in $MERCURY_ENV_FILE"

  # The tunnel exists only while a token does.
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    export COMPOSE_PROFILES=tunnel
  fi

  local args=(up -d --build --remove-orphans)
  # shellcheck disable=SC2206  # MERCURY_SERVICES is a space separated list on purpose
  local services=(${MERCURY_SERVICES:-})
  if [ "${#services[@]}" -gt 0 ]; then
    # A subset of services: the others are not orphans, leave them alone.
    args=(up -d --build "${services[@]}")
  fi
  [ "$pull" -eq 1 ] && args+=(--pull always)
  compose "${args[@]}"

  stack_sandbox_image "$pull"
  log "up. gateway: $(gateway_url)   (mercury doctor / mercury status)"
}

# Pull or build the sandbox image. Local name means build from sandbox/.
stack_sandbox_image() {
  local pull="${1:-0}"
  local img
  img="$(sandbox_image)"
  case "$img" in
    mercury-sandbox:local | agent-sandbox:*)  # agent-sandbox: the pre-0.1 local name
      log "building sandbox image $img"
      docker build -t "$img" "$MERCURY_ROOT/sandbox"
      ;;
    *)
      if [ "$pull" -eq 1 ] || ! docker image inspect "$img" >/dev/null 2>&1; then
        log "pulling sandbox image $img"
        docker pull "$img"
      fi
      ;;
  esac
}

# Usage: stack_down [--force]
#   compose down. Refuses while sandboxes run, because destroying the gateway
#   cuts them off mid-task and removing agentnet fails while they are attached.
stack_down() {
  local force=0
  case "${1:-}" in
    --force | -f) force=1; shift ;;
  esac
  local running
  running="$(running_sandboxes)"
  if [ -n "$running" ] && [ "$force" -eq 0 ]; then
    {
      echo "mercury: sandboxes are still running:"
      echo "$running" | sed 's/^/  /'
      echo "Stop them first (mercury kill <name>) or rerun with: mercury down --force"
    } >&2
    return 1
  fi
  log "this stops the gateway too: anything mid-task (Hermes, opencode-manager) loses its model endpoint"
  load_env
  [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && export COMPOSE_PROFILES=tunnel
  compose down "$@"
}

# Stop the services but keep everything in place for the next up.
stack_stop() {
  load_env
  compose stop "$@"
}

stack_status() {
  load_env
  echo "# stack"
  compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null ||
    compose ps
  echo
  echo "# sandboxes"
  docker ps --filter label=mercury.sandbox \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Label "mercury.branch"}}\t{{.Label "mercury.repo"}}'
}

# List the model names the gateway exposes.
stack_models() {
  load_env
  local resp
  resp="$(curl -fsS -m 10 "$(gateway_url)/models" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}")" || die "gateway not answering at $(gateway_url)"
  if have jq; then
    jq -r '.data[].id' <<<"$resp"
  else
    printf '%s\n' "$resp"
  fi
}

# Read-only health checks. Exit 1 if anything FAILs; warn and skip are fine.
stack_doctor() {
  local fails=0 docker_up=0
  report() { printf '%-5s %s\n' "$1" "$2"; }
  fail() { report FAIL "$1"; fails=$((fails + 1)); }

  report info "mercury $(mercury_version), $([ "$MERCURY_IN_CONTAINER" = 1 ] && echo 'in container' || echo 'on host')"

  if docker info >/dev/null 2>&1; then
    report ok "docker daemon reachable"
    docker_up=1
  else
    fail "docker daemon not reachable (DOCKER_HOST=${DOCKER_HOST:-default})"
  fi
  if docker compose version >/dev/null 2>&1; then
    report ok "docker compose available"
  else
    fail "docker compose plugin missing"
  fi

  if [ -f "$MERCURY_ENV_FILE" ]; then
    report ok "env file present ($MERCURY_ENV_FILE)"
  elif [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    report ok "no env file, keys taken from the environment"
  else
    fail "no env file at $MERCURY_ENV_FILE (cp .env.example .env)"
  fi
  load_env
  if [ -n "${LITELLM_MASTER_KEY:-}" ] && [ "$LITELLM_MASTER_KEY" != "sk-local-change-me" ]; then
    report ok "LITELLM_MASTER_KEY set"
  else
    fail "LITELLM_MASTER_KEY missing or still the placeholder"
  fi
  if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${OPENROUTER_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ]; then
    report ok "at least one provider key set"
  else
    fail "no provider key set (ANTHROPIC_API_KEY / OPENROUTER_API_KEY / OPENAI_API_KEY)"
  fi
  if [ -n "${SANDBOX_GIT_TOKEN:-}" ]; then
    report ok "SANDBOX_GIT_TOKEN set"
  else
    report warn "SANDBOX_GIT_TOKEN empty, non-interactive sandboxes cannot push"
  fi

  if [ "$docker_up" -eq 1 ]; then
    if [ -n "$(docker ps --filter name='^mercury-gateway$' --filter status=running -q)" ]; then
      report ok "gateway container running"
      if curl -fsS -m 5 "$(gateway_url)/models" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}" >/dev/null 2>&1; then
        report ok "gateway answers $(gateway_url)/models"
      else
        fail "gateway running but $(gateway_url)/models not answering (mercury logs gateway)"
      fi
    else
      report skip "gateway container not running (mercury up)"
      report skip "gateway endpoint (gateway not running)"
    fi
    if docker network inspect agentnet >/dev/null 2>&1; then
      report ok "agentnet network present"
    else
      report skip "agentnet network missing (mercury up)"
    fi
    local img
    img="$(sandbox_image)"
    if docker image inspect "$img" >/dev/null 2>&1; then
      report ok "sandbox image present ($img)"
    else
      report skip "sandbox image $img missing (mercury up builds or pulls it)"
    fi
    # RunningFor is humanized, so match >=24 hours or any day/week/month unit
    local orphans
    orphans="$(docker ps --filter label=mercury.sandbox --format '{{.Names}} (up {{.RunningFor}})' |
      grep -E '\((up )?((2[4-9]|[3-9][0-9]|[0-9]{3,}) hours|.*(day|week|month|year))' || true)"
    if [ -n "$orphans" ]; then
      report warn "sandboxes running for over 24h: $(echo "$orphans" | tr '\n' ' ')"
    else
      report ok "no sandboxes older than 24h"
    fi
  else
    report skip "gateway, network, image and sandbox checks (docker not reachable)"
  fi

  [ "$fails" -eq 0 ] || return 1
}
