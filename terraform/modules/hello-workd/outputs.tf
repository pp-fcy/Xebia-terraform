output "load_balancer_ip" {
  description = "Static IP of the Global Load Balancer"
  value       = module.load_balancer.external_ip
}

output "cloud_run_url" {
  description = "Direct Cloud Run URL (internal use / smoke tests). Production traffic goes through the Load Balancer."
  value       = google_cloud_run_v2_service.primary.uri
}

output "artifact_registry_url" {
  description = "Artifact Registry repository base URL for CI/CD tags"
  value       = local.registry_url
}
