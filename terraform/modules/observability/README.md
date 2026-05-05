# Module: observability (golden path)

Reusable Terraform module that gives **every IDP service** the same baseline
observability so on-call rotates without retraining and dashboards look
identical across the 17 product teams.

## What you get

| Resource | Purpose |
|----------|---------|
| `google_monitoring_dashboard.service` | One-pane-of-glass: req/s, instance count, latency p50/p95/p99, 5xx rate, error log rate. |
| `google_logging_metric.app_errors` | Counts `severity>=ERROR` log entries from the Cloud Run service. |
| `google_monitoring_uptime_check_config.service` | HTTPS probe against the Load Balancer (or custom domain). Optional. |
| `google_monitoring_alert_policy.errors` | Fires when error log rate > `var.error_rate_threshold` per minute for 5 minutes. |
| `google_monitoring_alert_policy.uptime` | Fires when the uptime probe fails for 5 minutes. Optional. |
| `google_monitoring_notification_channel.email` | One per email address in `var.alert_notification_emails`. |

## Usage

```hcl
module "observability" {
  source = "./modules/observability"

  project_id     = var.project_id
  app_name       = var.app_name
  primary_region = var.primary_region

  # Optional — wire to the LB IP exported from your service module
  uptime_check_host = module.hello_world.load_balancer_ip
  uptime_check_path = "/"

  alert_notification_emails = ["platform-oncall@fincore.example"]
}
```

Adding a new service to the platform is now: copy the block, change `app_name`,
`terraform apply`. No console clicks, no per-team dashboard divergence.

## Inputs

| Name | Description | Required |
|------|-------------|----------|
| `project_id` | GCP project ID. | yes |
| `app_name` | Service name (used in dashboard title, metric name, alert name). | yes |
| `primary_region` | Cloud Run region of the target service. | yes |
| `uptime_check_host` | Hostname/IP to probe (`""` disables the check). | no |
| `uptime_check_path` | HTTP path to probe (default `/`). | no |
| `alert_notification_emails` | List of emails. Empty = policies still created, no channels attached. | no |
| `error_rate_threshold` | Errors/minute that trip the alert (default `5`). | no |

## Outputs

| Name | Description |
|------|-------------|
| `dashboard_id` | Full resource ID of the dashboard. |
| `dashboard_url` | Direct console URL — surfaced in root `terraform output`. |
| `log_metric_name` | For ad-hoc Logs Explorer / MQL queries. |
| `alert_policy_error_rate` | Error-rate alert policy ID. |
| `alert_policy_uptime` | Uptime alert policy ID (`null` if no host configured). |
