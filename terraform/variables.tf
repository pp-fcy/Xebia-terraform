variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "primary_region" {
  description = "GCP region for the Cloud Run service"
  type        = string
  default     = "europe-west1"
}

variable "app_name" {
  description = "Application name – used as a prefix for all resource names"
  type        = string
  default     = "hello-world"
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
  description = "Minimum warm Cloud Run instances (1 eliminates cold starts)"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum Cloud Run instances"
  type        = number
  default     = 10
}

