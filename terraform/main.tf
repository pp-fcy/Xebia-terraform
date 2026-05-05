# Root composition for the FinCore IDP walking-stick demo.
#
# Two modules are stitched together here:
#
#   1. `what_time_is_it` — the sample service (Cloud Run + LB + Cloud Armor +
#      Artifact Registry). Single region — no canary, no blue/green.
#   2. `observability`   — the golden-path observability baseline (dashboard +
#      log-based error metric). Same module is reused by every service so
#      on-call sees a consistent shape.

module "what_time_is_it" {
  source          = "./modules/hello-world"
  project_id      = var.project_id
  primary_region  = var.primary_region
  app_name        = var.app_name
  container_image = var.container_image
  domain          = var.domain
  min_instances   = var.min_instances
  max_instances   = var.max_instances
}

module "observability" {
  source     = "./modules/observability"
  project_id = var.project_id
  app_name   = var.app_name
}
