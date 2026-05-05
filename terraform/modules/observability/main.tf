##############################################################################
# observability/main.tf
#
# Golden-path observability for any IDP service. Provisions:
#   - Cloud Monitoring dashboard (request count, latency p50/p95/p99, 5xx rate,
#     instance count) — one click for VP Eng / Sr Cloud Eng to see service health.
#   - Log-based metric counting Cloud Run application errors (used by the alert
#     policy and visible on the dashboard).
#   - Uptime check + alert policy on uptime failure (skipped if no host is set).
#   - Alert policy on high error rate, optionally wired to email channels.
#
# Why a separate module: the management summary calls out "unified dashboards,
# logs, metrics, and traces" as part of the golden path. Putting this in a
# reusable module means every new service gets the same baseline — a developer
# onboards by adding one `module "observability"` block, not by hand-rolling
# dashboards in the console.
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.24.0"
    }
  }
}

# ─── API enablement ─────────────────────────────────────────────────────────
resource "google_project_service" "monitoring" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ─── Notification channels (optional) ───────────────────────────────────────
resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.alert_notification_emails)

  project      = var.project_id
  display_name = "Email — ${each.value}"
  type         = "email"

  labels = {
    email_address = each.value
  }

  depends_on = [google_project_service.monitoring]
}

# ─── Log-based metric: application errors ───────────────────────────────────
# Counts ERROR-or-worse log entries from the Cloud Run service. The dashboard
# graphs it and the alert policy below fires on sustained spikes.
resource "google_logging_metric" "app_errors" {
  project = var.project_id
  name    = "${var.app_name}-app-errors"
  filter  = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${var.app_name}"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    display_name = "${var.app_name} application errors"
  }

  depends_on = [google_project_service.monitoring]
}

# ─── Uptime check (optional) ────────────────────────────────────────────────
resource "google_monitoring_uptime_check_config" "service" {
  count = var.uptime_check_host == "" ? 0 : 1

  project      = var.project_id
  display_name = "${var.app_name} — uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = var.uptime_check_path
    port           = "443"
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.uptime_check_host
    }
  }

  depends_on = [google_project_service.monitoring]
}

# ─── Alert policy: uptime check failure ─────────────────────────────────────
resource "google_monitoring_alert_policy" "uptime" {
  count = var.uptime_check_host == "" ? 0 : 1

  project      = var.project_id
  display_name = "${var.app_name} — uptime check failing"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type=\"uptime_url\"",
        "metric.label.check_id=\"${google_monitoring_uptime_check_config.service[0].uptime_check_id}\"",
      ])
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      trigger { count = 1 }

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]

  documentation {
    content   = "Uptime probe to https://${var.uptime_check_host}${var.uptime_check_path} has been failing for 5 minutes. Check Cloud Run revisions, Cloud Armor logs, and the Load Balancer health."
    mime_type = "text/markdown"
  }
}

# ─── Alert policy: high application error rate ──────────────────────────────
resource "google_monitoring_alert_policy" "errors" {
  project      = var.project_id
  display_name = "${var.app_name} — high error rate"
  combiner     = "OR"

  conditions {
    display_name = "Error log rate above threshold"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\" AND resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold
      trigger { count = 1 }

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [for c in google_monitoring_notification_channel.email : c.id]

  documentation {
    content   = "Cloud Run service `${var.app_name}` is logging more than ${var.error_rate_threshold} ERROR-or-worse entries per minute. Open the dashboard, then drill into Cloud Logging filtered by severity>=ERROR."
    mime_type = "text/markdown"
  }
}

# ─── Dashboard ──────────────────────────────────────────────────────────────
# Single pane of glass: every IDP service gets the same shape so on-call rotates
# without retraining. Layout: top row = traffic (req/s + active instances),
# middle row = latency percentiles, bottom row = errors.
resource "google_monitoring_dashboard" "service" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.app_name} — Service Overview"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Request count (req/s)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"run.googleapis.com/request_count\"",
                      "resource.type=\"cloud_run_revision\"",
                      "resource.label.service_name=\"${var.app_name}\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.location"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "req/s" }
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Active container instances"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"run.googleapis.com/container/instance_count\"",
                      "resource.type=\"cloud_run_revision\"",
                      "resource.label.service_name=\"${var.app_name}\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.location"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "instances" }
            }
          }
        },
        {
          yPos   = 4
          width  = 12
          height = 4
          widget = {
            title = "Request latency (p50 / p95 / p99)"
            xyChart = {
              dataSets = [
                for percentile in ["50", "95", "99"] : {
                  legendTemplate = "p${percentile}"
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = join(" AND ", [
                        "metric.type=\"run.googleapis.com/request_latencies\"",
                        "resource.type=\"cloud_run_revision\"",
                        "resource.label.service_name=\"${var.app_name}\"",
                      ])
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_DELTA"
                        crossSeriesReducer = "REDUCE_PERCENTILE_${percentile}"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = { label = "ms" }
            }
          }
        },
        {
          yPos   = 8
          width  = 6
          height = 4
          widget = {
            title = "5xx response codes"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"run.googleapis.com/request_count\"",
                      "resource.type=\"cloud_run_revision\"",
                      "resource.label.service_name=\"${var.app_name}\"",
                      "metric.label.response_code_class=\"5xx\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "5xx/s" }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 8
          width  = 6
          height = 4
          widget = {
            title = "Application error log rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\" AND resource.type=\"cloud_run_revision\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "errors/min" }
            }
          }
        },
      ]
    }
  })

  depends_on = [google_project_service.monitoring]
}
