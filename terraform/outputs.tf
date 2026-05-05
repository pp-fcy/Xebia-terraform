output "load_balancer_ip" {
  description = "Static IP of the Global Load Balancer – point your DNS A-record here"
  value       = module.what_time_is_it.load_balancer_ip
}

output "cloud_run_url" {
  description = "Direct Cloud Run URL (internal use / smoke tests). Production traffic goes through the Load Balancer."
  value       = module.what_time_is_it.cloud_run_url
}

output "artifact_registry_url" {
  description = "Artifact Registry repository base URL – used in CI/CD image tags"
  value       = module.what_time_is_it.artifact_registry_url
}

# Observability

output "dashboard_url" {
  description = "Direct console URL to the service overview dashboard. Open this in the demo browser to show 'unified dashboard' from the management summary."
  value       = module.observability.dashboard_url
}

