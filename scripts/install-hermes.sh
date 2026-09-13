#!/usr/bin/env bash
# Native Hermes install (macOS/Linux), official installer from Nous Research.
# Hermes stays native on purpose: ~/.hermes is its entire memory and you want
# that on a filesystem you back up, not inside a container.
set -euo pipefail
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
echo
echo "Now run:  source ~/.zshrc && hermes setup"
echo "In setup: point the provider at http://127.0.0.1:4000/v1 (the gateway) with"
echo "your LITELLM_MASTER_KEY, and pick the Docker terminal backend so shell work"
echo "runs in containers. To hand Hermes a task-sized sandbox, have it call:"
echo "  mercury sandbox -d <git-url> \"<task>\"        (or POST /api/sandboxes on :5004)"
