#!/usr/bin/env bash
# Per-sandbox credentials: mint the narrowest thing that will do the job and
# let it expire on its own. Both minters run in the controller, which is the
# only place the long-lived secrets live; the sandbox only ever sees the
# short-lived result.
#
#   creds_gateway_key <name> <model> <repo> <branch>
#       A LiteLLM virtual key limited to one model, a dollar budget and a
#       lifetime. Needs MERCURY_VIRTUAL_KEYS=1 (the gateway then has a
#       database, see compose.keys.yaml). Otherwise prints the master key.
#
#   creds_git_token <repo-url> <want-pr 0|1>
#       A GitHub App installation token scoped to that one repository, valid
#       for an hour, when GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID and
#       GITHUB_APP_PRIVATE_KEY_FILE (or GITHUB_APP_PRIVATE_KEY) are set and
#       the repo is on GitHub. Otherwise prints SANDBOX_GIT_TOKEN.

# The gateway's admin endpoints hang off the root, not /v1.
gateway_root() {
  local u
  u="$(gateway_url)"
  printf '%s' "${u%/v1}"
}

creds_virtual_keys_enabled() { [ "${MERCURY_VIRTUAL_KEYS:-0}" = "1" ]; }

creds_gateway_key() {
  local name="$1" model="$2" repo="$3" branch="$4"
  if ! creds_virtual_keys_enabled; then
    printf '%s' "$LITELLM_MASTER_KEY"
    return 0
  fi
  local body resp key
  body="$(jq -nc \
    --arg alias "$name" --arg model "$model" --arg repo "$repo" --arg branch "$branch" \
    --arg dur "${SANDBOX_KEY_TTL:-24h}" --argjson budget "${SANDBOX_BUDGET_USD:-5}" \
    '{key_alias: $alias, models: [$model], max_budget: $budget, duration: $dur,
      metadata: {mercury: "sandbox", repo: $repo, branch: $branch}}')"
  resp="$(curl -fsS -m 15 -X POST "$(gateway_root)/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H 'Content-Type: application/json' -d "$body")" ||
    die "could not mint a virtual key at $(gateway_root)/key/generate (is MERCURY_VIRTUAL_KEYS=1 and the gateway database up? mercury logs gateway)"
  key="$(jq -r '.key // empty' <<<"$resp")"
  [ -n "$key" ] || die "gateway returned no key: $resp"
  printf '%s' "$key"
}

# Revoke a virtual key early (they expire on their own otherwise).
creds_revoke_gateway_key() {
  creds_virtual_keys_enabled || return 0
  curl -fsS -m 15 -X POST "$(gateway_root)/key/delete" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg k "$1" '{keys: [$k]}')" >/dev/null 2>&1 || true
}

creds_github_app_enabled() {
  [ -n "${GITHUB_APP_ID:-}" ] && [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ] &&
    { [ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ] || [ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]; }
}

# owner/repo from a GitHub URL, empty for anything else.
github_repo_path() {
  local host="${GITHUB_HOST:-github.com}"
  case "$1" in
    https://"$host"/*/* | http://"$host"/*/*)
      local p="${1#*://"$host"/}"
      p="${p%.git}"
      p="${p%/}"
      [[ "$p" == */* ]] && [[ "$p" != */*/* ]] && printf '%s' "$p"
      ;;
  esac
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# A 9-minute RS256 JWT for the App, signed with its private key.
github_app_jwt() {
  local now keyfile header payload signing
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(jq -nc --argjson iat "$((now - 60))" --argjson exp "$((now + 540))" \
    --arg iss "$GITHUB_APP_ID" '{iat: $iat, exp: $exp, iss: $iss}' | tr -d '\n' | b64url)"
  signing="${header}.${payload}"
  if [ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]; then
    keyfile="$GITHUB_APP_PRIVATE_KEY_FILE"
  else
    keyfile="$(mktemp)"
    printf '%s\n' "$GITHUB_APP_PRIVATE_KEY" > "$keyfile"
  fi
  printf '%s.%s' "$signing" \
    "$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$keyfile" -binary | b64url)"
  [ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ] || rm -f "$keyfile"
}

creds_git_token() {
  local repo_url="$1" want_pr="${2:-0}" path
  path="$(github_repo_path "$repo_url")"
  if ! creds_github_app_enabled || [ -z "$path" ]; then
    printf '%s' "${SANDBOX_GIT_TOKEN:-}"
    return 0
  fi
  local perms='{contents: "write"}'
  [ "$want_pr" = "1" ] && perms='{contents: "write", pull_requests: "write"}'
  local body resp token
  body="$(jq -nc --arg r "${path#*/}" "{repositories: [\$r], permissions: $perms}")"
  resp="$(curl -fsS -m 20 -X POST \
    "${GITHUB_API_URL:-https://api.github.com}/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
    -H "Authorization: Bearer $(github_app_jwt)" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -d "$body")" || die "GitHub App token for $path refused (is the App installed on that repository with contents write?)"
  token="$(jq -r '.token // empty' <<<"$resp")"
  [ -n "$token" ] || die "GitHub returned no token: $resp"
  printf '%s' "$token"
}
