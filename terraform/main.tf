terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Local Docker Desktop / OrbStack / dockerd socket.
# For a remote host instead:  host = "ssh://you@remote-host"
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Isolated network. LiteLLM and sandboxes live here, sandboxes reach the
# gateway by the DNS name "gateway" and nothing on your LAN.
resource "docker_network" "agentnet" {
  name = "agentnet"
}

# ---- LiteLLM gateway -------------------------------------------------------

resource "docker_image" "litellm" {
  name = "ghcr.io/berriai/litellm:main-stable"
}

resource "docker_container" "gateway" {
  name    = "gateway"
  image   = docker_image.litellm.image_id
  restart = "unless-stopped"

  command = ["--config", "/app/config.yaml", "--port", "4000"]

  env = [
    "LITELLM_MASTER_KEY=${var.litellm_master_key}",
    "ANTHROPIC_API_KEY=${var.anthropic_api_key}",
    "OPENROUTER_API_KEY=${var.openrouter_api_key}",
  ]

  volumes {
    host_path      = abspath("${path.module}/../litellm/config.yaml")
    container_path = "/app/config.yaml"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.agentnet.name
  }

  # Exposed on localhost only, remote access goes via Tailscale, not the LAN
  ports {
    internal = 4000
    external = 4000
    ip       = "127.0.0.1"
  }
}

# ---- Sandbox base image ----------------------------------------------------

resource "docker_image" "sandbox" {
  name = "agent-sandbox:latest"
  build {
    context = abspath("${path.module}/../sandbox")
  }
  # Rebuild when the Dockerfile changes
  triggers = {
    dockerfile_sha = filesha256("${path.module}/../sandbox/Dockerfile")
  }
}

# ---- Cloudflare Tunnel (optional) ------------------------------------------
# Alternative (or addition) to Tailscale for remote access. Create a tunnel in
# the Cloudflare Zero Trust dashboard, put its token in .env as
# CLOUDFLARE_TUNNEL_TOKEN, and apply. Leave the token empty and none of this
# is created. Route hostnames to services in the dashboard, see the README.

resource "docker_image" "cloudflared" {
  count = var.cloudflare_tunnel_token == "" ? 0 : 1
  name  = "cloudflare/cloudflared:latest"
}

resource "docker_container" "cloudflared" {
  count   = var.cloudflare_tunnel_token == "" ? 0 : 1
  name    = "cloudflared"
  image   = docker_image.cloudflared[0].image_id
  restart = "unless-stopped"

  command = ["tunnel", "--no-autoupdate", "run"]

  env = ["TUNNEL_TOKEN=${var.cloudflare_tunnel_token}"]

  networks_advanced {
    name = docker_network.agentnet.name
  }

  # Lets tunnel routes reach services on the host (hermes-webui,
  # opencode-manager) as host.docker.internal, on plain Linux dockerd too
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}
