# Throwaway opencode sandbox. Multi-arch (amd64 and arm64), no credentials
# baked in: everything a run needs arrives as environment variables and is
# read by entrypoint.sh.
#
# Built locally by `mercury up` (SANDBOX_IMAGE=mercury-sandbox:local, the
# default) or pulled from ghcr.io/benkelly/mercury-sandbox. Rebuild whenever
# you want newer opencode: OPENCODE_VERSION pins it if you need to.
FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates ripgrep jq python3 python3-pip make \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force

# Non-root user, nothing in this image is precious. The node base image
# already owns uid 1000 as "node"; rename it so uid 1000 matches the tmpfs
# mounts the spawner sets up for /work and /home/agent.
RUN usermod -l agent -d /home/agent -m node && groupmod -n agent node

COPY entrypoint.sh /usr/local/bin/mercury-entrypoint

USER agent
WORKDIR /work

# Fail fast instead of waiting on a prompt when a remote needs auth we lack.
ENV GIT_TERMINAL_PROMPT=0

ENTRYPOINT ["mercury-entrypoint"]
