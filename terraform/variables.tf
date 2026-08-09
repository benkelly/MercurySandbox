variable "litellm_master_key" {
  type      = string
  sensitive = true
}

variable "anthropic_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "openrouter_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

# Populate from .env without retyping:
#   set -a; source ../.env; set +a
#   export TF_VAR_litellm_master_key="$LITELLM_MASTER_KEY"
#   export TF_VAR_anthropic_api_key="$ANTHROPIC_API_KEY"
#   export TF_VAR_openrouter_api_key="$OPENROUTER_API_KEY"
# Or use the helper: source ../scripts/tf-env.sh
