variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "primary_region" {
  description = "GCP region for the Cloud Run service"
  type        = string
}

variable "app_name" {
  description = "Application name – resource name prefix and Cloud Run service name"
  type        = string
}

variable "container_image" {
  description = "Full container image reference to deploy (e.g. europe-west1-docker.pkg.dev/.../hello-world:sha-abc). CI/CD always passes this via -var. Defaults to a public hello-world for initial bootstrap."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
}

variable "domain" {
  description = "Custom domain for HTTPS LB (empty = HTTP only)"
  type        = string
}

variable "min_instances" {
  description = "Minimum Cloud Run instances"
  type        = number
}

variable "max_instances" {
  description = "Maximum Cloud Run instances"
  type        = number
}
