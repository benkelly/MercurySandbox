#!/usr/bin/env bash
# Native Hermes install (macOS/Linux), official installer from Nous Research
set -euo pipefail
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
echo
echo "Now run:  source ~/.zshrc && hermes setup"
echo "In setup: point the provider at http://localhost:4000/v1 (LiteLLM),"
echo "and pick the Docker terminal backend so shell work runs in containers."
