output "load_balancer_ip" {
  description = "Static IP of the Global Load Balancer – point your DNS A-record here"
  value       = module.what_time_is_it.load_balancer_ip
}

output "cloud_run_url_primary" {
  description = "Direct Cloud Run URL in primary region (internal use / smoke tests)"
  value       = module.what_time_is_it.cloud_run_url_primary
}

output "cloud_run_url_secondary" {
  description = "Direct Cloud Run URL in secondary region (internal use / smoke tests)"
  value       = module.what_time_is_it.cloud_run_url_secondary
}

output "artifact_registry_url" {
  description = "Artifact Registry repository base URL – used in CI/CD image tags"
  value       = module.what_time_is_it.artifact_registry_url
}
