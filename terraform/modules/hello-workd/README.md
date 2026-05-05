# Module: `what-time-is-it`

> Module path is historical — the sample service in this repo is now
> [`hello-world/`](../../../hello-world/). The module name is preserved so
> existing state references don't churn.

Deploys a single-region Cloud Run service on GCP behind a Global HTTPS Load
Balancer, plus the security and registry plumbing it needs:

- Required APIs (`google_project_service`)
- Artifact Registry (Docker) with cleanup policy
- Cloud Armor (WAF / OWASP CRS + rate limiting)
- Single-region Cloud Run with `INTERNAL_LOAD_BALANCER` ingress
- Serverless NEG + Global HTTPS Load Balancer

No canary, no blue/green, no second region — by design. See the cuts table in
[`docs/IDP_ARCHITECTURE.md`](../../../docs/IDP_ARCHITECTURE.md#what-is-intentionally-not-in-the-walking-stick).

## Usage (from root)

```hcl
module "what_time_is_it" {
  source = "./modules/what-time-is-it"

  project_id      = var.project_id
  primary_region  = "europe-west1"
  app_name        = "hello-world"
  container_image = "..."   # passed via -var in CI; defaults to a public hello-world for bootstrap
  domain          = ""
  min_instances   = 1
  max_instances   = 10
}
```

## container_image

`container_image` is **not** stored in tfvars. It is passed at apply time:

```bash
terraform apply \
  -var-file=env/prod.tfvars \
  -var="container_image=europe-west1-docker.pkg.dev/<project>/<repo>/<name>:<sha>"
```

The variable defaults to `us-docker.pkg.dev/cloudrun/container/hello:latest` so
the very first infrastructure bootstrap works without a built image.

CI/CD (the `deploy` job in `.github/workflows/terraform.yml`, called by
`build-image.yml`) always overrides this with the SHA-tagged image built in the
same pipeline run.
