##############################################################################
# observability/variables.tf
##############################################################################

variable "project_id" {
  description = "GCP project ID where the observability resources live."
  type        = string
}

variable "app_name" {
  description = "Application/service name. Used to scope the dashboard and log metric."
  type        = string
}
