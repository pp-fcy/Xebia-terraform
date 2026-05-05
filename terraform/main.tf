# Root composition for the FinCore IDP walking-stick demo.
#
# Two modules are stitched together here, in the order a stream-aligned product
# team consumes the platform:
#
#   1. `what_time_is_it` — the sample service (Cloud Run + LB + Cloud Armor +
#      Artifact Registry). Single region — no canary, no blue/green. The point
#      of the walking-stick is the *platform shape*, not deploy sophistication.
#   2. `observability`   — the golden-path observability baseline (dashboard +
#      log-based metric + uptime check + alerts). Same module is reused by
#      every service so on-call sees a consistent shape.
#
# Adding a second service to the platform = duplicate this composition pattern
# (or run a second workspace/state). The point of the IDP is that no team needs
# to re-design these blocks from scratch.

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
  source = "./modules/observability"

  project_id = var.project_id
  app_name   = var.app_name

  # Probe the Load Balancer IP exported from the service module so the uptime
  # check exercises the same path real users take (LB → Cloud Armor → Cloud Run).
  uptime_check_host = module.what_time_is_it.load_balancer_ip
  uptime_check_path = "/"

  alert_notification_emails = var.alert_notification_emails
  error_rate_threshold      = var.error_rate_threshold
}
