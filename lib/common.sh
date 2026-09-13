#!/usr/bin/env bash
# Shared helpers for bin/mercury and the lib/*.sh it sources.
#
# Expects MERCURY_ROOT to be set by the caller (the repo checkout on a host,
# /opt/mercury inside the controller image). Everything else is derived from
# the environment so the same code runs on a laptop, in the mercury container
# and inside the Home Assistant add-on.

# The .env holding keys. Inside a container the same values usually arrive
# through the environment instead, so a missing file is not an error here;
# commands that truly need the file (up) check for it themselves.
MERCURY_ENV_FILE="${MERCURY_ENV_FILE:-$MERCURY_ROOT/.env}"

# Set to 1 by the controller image. Changes only defaults: where the gateway
# is reachable and which address mercuryd binds.
MERCURY_IN_CONTAINER="${MERCURY_IN_CONTAINER:-0}"

# Compose project name, fixed so every context manages the same containers.
MERCURY_PROJECT="${MERCURY_PROJECT:-mercury}"

log() { printf 'mercury: %s\n' "$*" >&2; }
die() { log "$@"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Load the .env into the environment (exported) if it exists.
load_env() {
  if [ -f "$MERCURY_ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$MERCURY_ENV_FILE"
    set +a
  fi
}

# Refuse to continue without a .env, with the fix in the message.
require_env_file() {
  [ -f "$MERCURY_ENV_FILE" ] ||
    die ".env missing at $MERCURY_ENV_FILE (cp .env.example .env and fill it in)"
}

# Where this process reaches the gateway. Inside agentnet that is the service
# name; on the host it is the published loopback port.
gateway_url() {
  if [ -n "${MERCURY_GATEWAY_URL:-}" ]; then
    printf '%s' "$MERCURY_GATEWAY_URL"
  elif [ "$MERCURY_IN_CONTAINER" = "1" ]; then
    printf 'http://gateway:4000/v1'
  else
    printf 'http://127.0.0.1:%s/v1' "${GATEWAY_PORT:-4000}"
  fi
}

# The sandbox image to run. Default builds locally from sandbox/; set
# SANDBOX_IMAGE to the published ghcr.io/benkelly/mercury-sandbox:<tag> to pull
# instead (what the Home Assistant add-on does).
sandbox_image() { printf '%s' "${SANDBOX_IMAGE:-mercury-sandbox:local}"; }

# docker compose against this stack. --env-file is passed explicitly so the
# add-on can keep its generated .env outside the checkout.
compose() {
  local args=(--project-name "$MERCURY_PROJECT" -f "$MERCURY_ROOT/compose.yaml")
  # Virtual keys need the gateway database, which lives in an override file
  # so the base stack never carries an empty DATABASE_URL.
  [ "${MERCURY_VIRTUAL_KEYS:-0}" = "1" ] && args+=(-f "$MERCURY_ROOT/compose.keys.yaml")
  [ -f "$MERCURY_ENV_FILE" ] && args+=(--env-file "$MERCURY_ENV_FILE")
  docker compose "${args[@]}" "$@"
}

# Which backend runs sandboxes: docker (default) or kubernetes.
sandbox_backend() { printf '%s' "${SANDBOX_BACKEND:-docker}"; }

# Names of running sandbox containers, one per line.
running_sandboxes() {
  docker ps --filter label=mercury.sandbox --format '{{.Names}}' 2>/dev/null || true
}

mercury_version() {
  if [ -f "$MERCURY_ROOT/VERSION" ]; then
    tr -d '[:space:]' < "$MERCURY_ROOT/VERSION"
  else
    printf 'dev'
  fi
}
