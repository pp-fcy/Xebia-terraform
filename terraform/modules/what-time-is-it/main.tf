terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.24.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "7.24.0"
    }
  }
}

locals {
  # Artifact Registry base URL — used by CI/CD to tag and push images.
  registry_url = "${var.primary_region}-docker.pkg.dev/${var.project_id}/${var.app_name}"
  # Image is always supplied by the caller via var.container_image.
  # CI/CD (release.yml) passes the newly built SHA-tagged image on every release.
  # The first-ever terraform apply uses the variable default (hello-world).
  runtime_image = var.container_image
}

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "artifact_registry" {
  source  = "GoogleCloudPlatform/artifact-registry/google"
  version = "0.8.2"

  project_id    = var.project_id
  location      = var.primary_region
  repository_id = var.app_name
  format        = "DOCKER"
  description   = "Docker images for ${var.app_name}"

  cleanup_policies = {
    keep-recent = {
      action = "KEEP"
      most_recent_versions = {
        keep_count = 10
      }
    }
    delete-stale = {
      action = "DELETE"
      condition = {
        older_than = "2592000s"
        tag_state  = "ANY"
      }
    }
  }

  depends_on = [google_project_service.apis]
}


module "cloud_armor" {
  source  = "GoogleCloudPlatform/cloud-armor/google"
  version = "7.0.0"

  project_id                  = var.project_id
  name                        = "${var.app_name}-security-policy"
  description                 = "WAF + DDoS protection for ${var.app_name}"
  type                        = "CLOUD_ARMOR"
  default_rule_action         = "allow"
  layer_7_ddos_defense_enable = true

  pre_configured_rules = {
    sqli = {
      action          = "deny(403)"
      priority        = 1000
      description     = "OWASP CRS - SQL Injection"
      target_rule_set = "sqli-v33-stable"
    }
    xss = {
      action          = "deny(403)"
      priority        = 1001
      description     = "OWASP CRS - Cross-Site Scripting"
      target_rule_set = "xss-v33-stable"
    }
    lfi = {
      action          = "deny(403)"
      priority        = 1002
      description     = "OWASP CRS - Local File Inclusion"
      target_rule_set = "lfi-v33-stable"
    }
    rfi = {
      action          = "deny(403)"
      priority        = 1003
      description     = "OWASP CRS - Remote File Inclusion"
      target_rule_set = "rfi-v33-stable"
    }
    rce = {
      action          = "deny(403)"
      priority        = 1004
      description     = "OWASP CRS - Remote Code Execution"
      target_rule_set = "rce-v33-stable"
    }
    scanner = {
      action          = "deny(403)"
      priority        = 1005
      description     = "OWASP CRS - Scanner detection"
      target_rule_set = "scannerdetection-v33-stable"
    }
  }

  security_rules = {
    rate_limit = {
      action        = "throttle"
      priority      = 2000
      description   = "Rate-limit: 100 req/min per IP"
      src_ip_ranges = ["*"]
      rate_limit_options = {
        exceed_action                        = "deny(429)"
        rate_limit_http_request_count        = 100
        rate_limit_http_request_interval_sec = 60
        ban_http_request_count               = 300
        ban_http_request_interval_sec        = 60
        ban_duration_sec                     = 300
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Cloud Run services are inlined (not via the external GoogleCloudPlatform module)
# so that Terraform fully owns the image and traffic on every apply.
# CI/CD passes container_image via -var; blue/green is achieved by targeting
# the primary resource first, smoke-testing, then applying the full config.

resource "google_cloud_run_v2_service" "primary" {
  project             = var.project_id
  name                = var.app_name
  location            = var.primary_region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  template {
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = local.runtime_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 5
        http_get {
          path = "/"
          port = 8080
        }
      }

      liveness_probe {
        period_seconds    = 30
        timeout_seconds   = 5
        failure_threshold = 3
        http_get {
          path = "/"
          port = 8080
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [google_project_service.apis, module.artifact_registry]
}

resource "google_cloud_run_v2_service_iam_member" "primary_invoker" {
  project  = var.project_id
  location = var.primary_region
  name     = google_cloud_run_v2_service.primary.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "secondary" {
  project             = var.project_id
  name                = var.app_name
  location            = var.secondary_region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  template {
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = local.runtime_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 5
        http_get {
          path = "/"
          port = 8080
        }
      }

      liveness_probe {
        period_seconds    = 30
        timeout_seconds   = 5
        failure_threshold = 3
        http_get {
          path = "/"
          port = 8080
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [google_project_service.apis, module.artifact_registry]
}

resource "google_cloud_run_v2_service_iam_member" "secondary_invoker" {
  project  = var.project_id
  location = var.secondary_region
  name     = google_cloud_run_v2_service.secondary.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_compute_region_network_endpoint_group" "primary" {
  project               = var.project_id
  name                  = "${var.app_name}-neg-${var.primary_region}"
  network_endpoint_type = "SERVERLESS"
  region                = var.primary_region

  cloud_run {
    service = var.app_name
  }

  depends_on = [google_cloud_run_v2_service.primary]
}

resource "google_compute_region_network_endpoint_group" "secondary" {
  project               = var.project_id
  name                  = "${var.app_name}-neg-${var.secondary_region}"
  network_endpoint_type = "SERVERLESS"
  region                = var.secondary_region

  cloud_run {
    service = var.app_name
  }

  depends_on = [google_cloud_run_v2_service.secondary]
}

module "load_balancer" {
  source  = "terraform-google-modules/lb-http/google//modules/serverless_negs"
  version = "14.2.0"

  project = var.project_id
  name    = var.app_name

  ssl                             = var.domain != ""
  managed_ssl_certificate_domains = var.domain != "" ? [var.domain] : []
  https_redirect                  = var.domain != ""

  backends = {
    default = {
      description = "Primary and secondary Cloud Run backends"
      groups = [
        { group = google_compute_region_network_endpoint_group.primary.id },
        { group = google_compute_region_network_endpoint_group.secondary.id }
      ]
      enable_cdn      = false
      security_policy = module.cloud_armor.policy.self_link
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
      iap_config = {
        enable = false
      }
    }
  }
}
