# The LiteLLM gateway with this stack's model routing baked in. Building a
# tiny image instead of bind-mounting config.yaml means the compose file has
# no host paths in it, so it applies unchanged from a laptop, a server, or
# from inside the Home Assistant add-on (where the host filesystem is not
# ours to mount from).
#
# Pinned deliberately: this container holds every provider key, so it must
# not change under you. To bump, pick a newer main-vX.Y.Z-stable tag from
# https://github.com/BerriAI/litellm/releases and run `mercury up`.
FROM ghcr.io/berriai/litellm:main-v1.83.14-stable

COPY config.yaml /app/config.yaml

# The upstream entrypoint is LiteLLM's own launcher, which takes these flags.
CMD ["--config", "/app/config.yaml", "--port", "4000"]
