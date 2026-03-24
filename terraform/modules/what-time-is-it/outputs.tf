output "load_balancer_ip" {
  description = "Static IP of the Global Load Balancer"
  value       = module.load_balancer.external_ip
}

output "cloud_run_url_primary" {
  description = "Cloud Run URL – primary region"
  value       = google_cloud_run_v2_service.primary.uri
}

output "cloud_run_url_secondary" {
  description = "Cloud Run URL – secondary region"
  value       = google_cloud_run_v2_service.secondary.uri
}

output "artifact_registry_url" {
  description = "Artifact Registry repository base URL for CI/CD tags"
  value       = local.registry_url
}
