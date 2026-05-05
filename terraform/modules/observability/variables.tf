##############################################################################
# observability/variables.tf
#
# Inputs for the observability "golden path" module. Every IDP-managed service
# gets the same baseline (dashboard + uptime check + error log-metric + alert)
# by calling this module from its own composition.
##############################################################################

variable "project_id" {
  description = "GCP project ID where the observability resources live."
  type        = string
}

variable "app_name" {
  description = "Application/service name. Used to scope dashboards, metrics and alert resources so multiple services can coexist in one project."
  type        = string
}

variable "primary_region" {
  description = "Primary region of the Cloud Run service the dashboard/uptime check should target."
  type        = string
}

variable "uptime_check_host" {
  description = "Hostname or IP the uptime check probes (typically the Global Load Balancer IP or a custom domain). Empty disables the uptime check."
  type        = string
  default     = ""
}

variable "uptime_check_path" {
  description = "HTTP path the uptime check requests."
  type        = string
  default     = "/"
}

variable "alert_notification_emails" {
  description = "Email addresses that receive alert notifications. Empty list = create the policy but no notification channel (still visible in the console)."
  type        = list(string)
  default     = []
}

variable "error_rate_threshold" {
  description = "Errors per minute that trip the high-error-rate alert."
  type        = number
  default     = 5
}
