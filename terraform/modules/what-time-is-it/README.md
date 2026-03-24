# Module: `what-time-is-it`

Deploys the **what-time-is-it** app on GCP:

- Required APIs
- Artifact Registry (Docker)
- Cloud Armor (WAF / OWASP CRS + rate limiting)
- Dual-region Cloud Run (internal LB ingress only)
- Serverless NEGs + Global HTTPS Load Balancer

## Usage (from root)

```hcl
module "what_time_is_it" {
  source = "./modules/what-time-is-it"

  project_id       = var.project_id
  primary_region   = "europe-west1"
  secondary_region = "europe-west4"
  app_name         = "what-time-is-it"
  container_image  = "..."   # pass via -var in CI; defaults to hello-world for bootstrap
  domain           = ""
  min_instances    = 1
  max_instances    = 10
}
```

## container_image

`container_image` is **not** stored in tfvars. It is passed at apply time:

```bash
terraform apply \
  -var-file=env/prod.tfvars \
  -var="container_image=europe-west1-docker.pkg.dev/<project>/<repo>/<name>:<sha>"
```

The variable defaults to `us-docker.pkg.dev/cloudrun/container/hello:latest` so the very first infrastructure bootstrap works without a built image.

CI/CD (`release.yml`) always overrides this with the SHA-tagged image built in the same pipeline run.
