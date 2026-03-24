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

project_id       = "bux-project-490819"
primary_region   = "europe-west1"
secondary_region = "europe-west4"
app_name         = "what-time-is-it"

# Optional: set to your domain to enable HTTPS with a Google-managed cert.
# Leave empty for HTTP-only (useful during initial setup).
domain = ""

# Cloud Run scaling
min_instances = 1
max_instances = 4
