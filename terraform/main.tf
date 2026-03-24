# Root composition: enable the what-time-is-it stack as a module.
# Add more modules here (e.g. other services) without mixing them into app internals.

module "what_time_is_it" {
  source = "./modules/what-time-is-it"

  project_id       = var.project_id
  primary_region   = var.primary_region
  secondary_region = var.secondary_region
  app_name         = var.app_name
  container_image  = var.container_image
  domain           = var.domain
  min_instances    = var.min_instances
  max_instances    = var.max_instances
}
