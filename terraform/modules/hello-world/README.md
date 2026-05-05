# Module: `hello-world`

Deploys the full application stack for a single Cloud Run service:

- **Artifact Registry** — Docker repository with cleanup policies (keep 10 latest, delete after 30 days)
- **Cloud Run v2** — serverless container service, internal ingress (LB only)
- **Cloud Armor** — WAF + DDoS protection (OWASP CRS rules: SQLi, XSS, LFI, RFI, RCE, Scanner; rate-limit 100 req/min/IP)
- **Global HTTP(S) Load Balancer** — optional managed SSL certificate when `domain` is set

## Usage

```hcl
module "hello_world" {
  source = "./modules/hello-world"

  project_id      = var.project_id
  primary_region  = var.primary_region
  app_name        = var.app_name
  container_image = var.container_image
  domain          = var.domain
  min_instances   = var.min_instances
  max_instances   = var.max_instances
}
```

## Inputs

| Name | Description | Required |
|---|---|---|
| `project_id` | GCP project ID | yes |
| `primary_region` | GCP region (e.g. `europe-west1`) | yes |
| `app_name` | Application name — used as Cloud Run service name and Artifact Registry repo ID | yes |
| `container_image` | Full image reference to deploy | yes |
| `domain` | Custom domain for managed SSL cert (leave empty for HTTP-only) | no |
| `min_instances` | Minimum Cloud Run instances | no |
| `max_instances` | Maximum Cloud Run instances | no |

## Outputs

| Name | Description |
|---|---|
| `load_balancer_ip` | Global LB static IP |
| `cloud_run_url` | Direct Cloud Run URL (internal only) |
| `artifact_registry_url` | Artifact Registry base URL |
