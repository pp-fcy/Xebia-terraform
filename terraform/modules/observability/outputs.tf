output "dashboard_id" {
  description = "Cloud Monitoring dashboard ID. Open at https://console.cloud.google.com/monitoring/dashboards/builder/<dashboard_id>?project=<project>."
  value       = google_monitoring_dashboard.service.id
}

output "dashboard_url" {
  description = "Direct console URL to the service dashboard — paste into the demo browser."
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${reverse(split("/", google_monitoring_dashboard.service.id))[0]}?project=${var.project_id}"
}

output "log_metric_name" {
  description = "Name of the log-based error metric — useful for ad-hoc PromQL/MQL queries."
  value       = google_logging_metric.app_errors.name
}

output "alert_policy_error_rate" {
  description = "Resource ID of the high-error-rate alert policy."
  value       = google_monitoring_alert_policy.errors.id
}

output "alert_policy_uptime" {
  description = "Resource ID of the uptime-failure alert policy (null when no uptime check is configured)."
  value       = try(google_monitoring_alert_policy.uptime[0].id, null)
}
