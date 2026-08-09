output "gateway_url" {
  value       = "http://localhost:4000/v1"
  description = "OpenAI-compatible endpoint for Hermes, opencode and opencode-manager"
}

output "gateway_url_from_containers" {
  value       = "http://gateway:4000/v1"
  description = "Endpoint as seen from inside the agentnet Docker network"
}

output "sandbox_image" {
  value       = "agent-sandbox:latest"
  description = "Throwaway opencode image, spawn with sandbox/run-sandbox.sh"
}
