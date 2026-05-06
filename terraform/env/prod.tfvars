##############################################################################
# Production environment – terraform/env/prod.tfvars
#
# Used by:
#   terraform plan  -var-file=env/prod.tfvars [-var="container_image=<img>"]
#   terraform apply -var-file=env/prod.tfvars  -var="container_image=<img>"
#
# container_image is NOT set here because CI/CD always passes it via -var.
# The first-ever bootstrap (no image built yet) uses the hello-world default
# defined in variables.tf.
##############################################################################

project_id     = "bux-project-490819"
primary_region = "europe-west1"
app_name       = "hello-world"

domain = ""

# Cloud Run scaling
min_instances = 1
max_instances = 4

# ─── Observability ─────────────────────────────────────────────
# Add real on-call addresses to wire alerts to email. Left empty during the
# demo: dashboards + alert policies are still created, just without channels.
# alert_notification_emails = ["platform-oncall@fincore.example"]
# error_rate_threshold      = 5
