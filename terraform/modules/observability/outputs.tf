output "dashboard_id" {
  description = "Cloud Monitoring dashboard resource ID."
  value       = google_monitoring_dashboard.service.id
}

output "dashboard_url" {
  description = "Direct console URL to the service dashboard."
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${reverse(split("/", google_monitoring_dashboard.service.id))[0]}?project=${var.project_id}"
}

output "log_metric_name" {
  description = "Name of the log-based error metric — useful for ad-hoc MQL queries."
  value       = google_logging_metric.app_errors.name
}
