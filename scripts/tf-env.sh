#!/usr/bin/env bash
# source this from terraform/: loads ../.env into TF_VAR_* for terraform apply
set -a; source "$(dirname "${BASH_SOURCE[0]}")/../.env"; set +a
export TF_VAR_litellm_master_key="$LITELLM_MASTER_KEY"
export TF_VAR_anthropic_api_key="${ANTHROPIC_API_KEY:-}"
export TF_VAR_openrouter_api_key="${OPENROUTER_API_KEY:-}"
