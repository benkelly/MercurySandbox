# Throwaway opencode sandbox. Multi-arch (works on the M4's arm64).
# Rebuild when you want newer opencode: terraform apply, or
#   docker build -t agent-sandbox:latest sandbox/

FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates ripgrep jq python3 python3-pip make \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g opencode-ai

# Non-root user, nothing in this image is precious
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /work

# opencode reads an OpenAI-compatible endpoint from its config, which
# run-sandbox.sh writes at launch so the image itself holds zero secrets.
ENTRYPOINT ["/bin/bash"]
