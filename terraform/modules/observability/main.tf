##############################################################################
# observability/main.tf
#
# Golden-path observability for any IDP service. Provisions:
#   - Cloud Monitoring dashboard (request count, latency p50/p95/p99, 5xx rate,
#     instance count) — one click for VP Eng / Sr Cloud Eng to see service health.
#   - Log-based metric counting Cloud Run application errors (graphed on the
#     dashboard's "Application error log rate" tile).
#
# Why a separate module: putting this in a reusable module means every new
# service gets the same baseline — a developer onboards by adding one
# `module "observability"` block, not by hand-rolling dashboards in the console.
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

# ─── Log-based metric: application errors ───────────────────────────────────
# Counts ERROR-or-worse log entries from the Cloud Run service.
# Graphed on the dashboard's "Application error log rate" tile.
resource "google_logging_metric" "app_errors" {
  project = var.project_id
  name    = "${var.app_name}-app-errors"
  filter  = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${var.app_name}"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "${var.app_name} application errors"
  }

  depends_on = [google_project_service.monitoring]
}

# ─── Dashboard ──────────────────────────────────────────────────────────────
# Single pane of glass: every IDP service gets the same shape so on-call
# rotates without retraining. Layout: top row = traffic (req/s + active
# instances), middle row = latency percentiles, bottom row = errors.
resource "google_monitoring_dashboard" "service" {
  project = var.project_id
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
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\" AND resource.type=\"cloud_run_revision\""
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
