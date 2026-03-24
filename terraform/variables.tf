variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region for Cloud Run (low-latency for EU users)"
  type        = string
  default     = "europe-west1"
}

variable "secondary_region" {
  description = "Secondary GCP region for Cloud Run (HA failover)"
  type        = string
  default     = "europe-west4"
}

variable "app_name" {
  description = "Application name – used as a prefix for all resource names"
  type        = string
  default     = "what-time-is-it"
}

variable "container_image" {
  description = "Full container image reference to deploy. CI/CD always passes this via -var. Defaults to hello-world for initial bootstrap."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
}

variable "domain" {
  description = "Custom domain for the HTTPS load balancer (leave empty for HTTP-only)"
  type        = string
  default     = ""
}

variable "min_instances" {
  description = "Minimum warm Cloud Run instances per region (1 eliminates cold starts)"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum Cloud Run instances per region"
  type        = number
  default     = 10
}
