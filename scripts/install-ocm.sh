#!/usr/bin/env bash
# opencode-manager via its own docker compose
set -euo pipefail
TARGET="${HOME}/opencode-manager"
[ -d "$TARGET" ] || git clone https://github.com/chriswritescode-dev/opencode-manager.git "$TARGET"
cd "$TARGET"
if [ ! -f .env ]; then
  cp .env.example .env
  echo "AUTH_SECRET=$(openssl rand -base64 32)" >> .env
fi
docker compose up -d
echo "opencode-manager: http://localhost:5003 (create the admin account on first visit)"
echo "Point its AI config at http://host.docker.internal:4000/v1 with your LITELLM_MASTER_KEY."
