# GCS backend settings are loaded per environment from env/<env>.backend.hcl
# (separate state prefix per env — do not share one backend block across prod and dev).
#
# First time (pick one):
#   terraform init -backend-config=env/prod.backend.hcl
#   terraform init -backend-config=env/dev.backend.hcl
#
# Switch environment later:
#   terraform init -reconfigure -backend-config=env/prod.backend.hcl
#
# Or: ./scripts/terraform-init-env.sh prod   # same as above
terraform {
  backend "gcs" {}
}
