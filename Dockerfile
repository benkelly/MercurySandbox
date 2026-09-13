# The mercury controller image: the same CLI you run on a host, packaged with
# the Docker CLI, compose, kubectl (for the Kubernetes backend) and mercuryd. It manages the stack and spawns
# sandboxes on the host's Docker through the mounted socket, which makes it
# root-equivalent on that host: publish its port on loopback or behind
# Tailscale only. The Home Assistant add-on builds FROM this image.
FROM alpine:3.24.1

# Alpine packages are deliberately unpinned: the image is rebuilt on every
# release and follows the distribution's security updates.
# hadolint ignore=DL3018
RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      docker-cli \
      docker-cli-compose \
      git \
      jq \
      kubectl \
      openssh-client-default \
      openssl \
      python3 \
      tini

WORKDIR /opt/mercury
COPY VERSION compose.yaml ./
COPY bin/ bin/
COPY lib/ lib/
COPY gateway/ gateway/
COPY sandbox/ sandbox/
COPY mercuryd/ mercuryd/
COPY scripts/ scripts/

ENV MERCURY_ROOT=/opt/mercury \
    MERCURY_IN_CONTAINER=1 \
    MERCURY_BIND=0.0.0.0 \
    MERCURY_PORT=5004 \
    PATH=/opt/mercury/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 5004

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5004/api/health || exit 1

ENTRYPOINT ["tini", "--", "mercury"]
CMD ["serve"]
