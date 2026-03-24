terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Cloud Run v2 module (0.25.x) requires 7.x (IAP + Cloud Run schema). lb-http >= 13 uses google < 8.
      version = "7.24.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "7.24.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}
