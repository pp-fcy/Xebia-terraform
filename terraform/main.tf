# Root composition – two modules stitched together:
#
#   1. `hello_world`   — the sample service (Cloud Run + LB + Cloud Armor +
#      Artifact Registry). Single region — no canary, no blue/green.
#   2. `observability` — golden-path observability baseline (dashboard +
#      log-based error metric).

module "hello_world" {
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
