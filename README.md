# Platform Golden Path — Hello World Service

A minimal end-to-end platform example on Google Cloud: a Python HTTP service deployed via Terraform and GitHub Actions, with security scanning and observability built in.

## What's in this repo

| Directory | What it is |
|-----------|-----------|
| [`hello-world/`](hello-world/) | Python HTTP service (`/` → `Hello World`, `/healthz` → `ok`) |
| [`terraform/`](terraform/) | Infrastructure: Cloud Run, Artifact Registry, Global LB, Cloud Armor, Monitoring dashboard |
| [`.github/workflows/`](.github/workflows/) | CI/CD: pre-commit → build → Trivy scan → deploy + smoke test |

## Architecture

```
GitHub push
    │
    ├─ Pre-commit (lint, fmt, secret scan, Checkov IaC scan)
    │
    ├─ Build Image (Cloud Build → Artifact Registry)
    │
    ├─ Trivy scan (CVE gate — blocks HIGH/CRITICAL before deploy)
    │
    └─ Deploy (Terraform apply → Cloud Run → smoke test via Load Balancer)
```

**GCP resources managed by Terraform:**

- **Cloud Run** — single-region service (`europe-west1`), internal ingress only
- **Global Load Balancer** — HTTPS termination, static IP
- **Cloud Armor** — WAF (OWASP ruleset) + rate limiting
- **Artifact Registry** — Docker image repository
- **Cloud Monitoring** — dashboard + log-based error metric

## Prerequisites

- `gcloud` CLI authenticated
- `terraform` >= 1.5
- GitHub Actions secrets: `WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`

## First-time setup

```bash
# Bootstrap GCP project (WIF, state bucket, IAM roles)
./scripts/init-project.sh

# Initialise Terraform backend
cd terraform
terraform init -backend-config=env/prod.backend.hcl

# First apply (deploys hello-world placeholder image)
terraform plan  -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```

## Local development

```bash
# Install pre-commit hooks
pip install -r requirements-dev.txt
pre-commit install

# Run all checks
pre-commit run --all-files

# Run the service locally
cd hello-world
python server.py        # listens on :8080
curl localhost:8080/
curl localhost:8080/healthz
```

## CI/CD workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `pre-commit.yml` | PR / push to main | Terraform fmt/validate/tflint, secret scan (gitleaks), Checkov IaC + Dockerfile + Actions scan |
| `build-image.yml` | Push to main touching `hello-world/` | Cloud Build → Trivy CVE scan → Terraform deploy → smoke test |
| `terraform.yml` | Push to main touching `terraform/` | Terraform plan (on PR) / apply (on merge) |
| `destroy.yml` | Manual only | Destroy all resources (requires typing `destroy` to confirm) |

## Environments

| File | Purpose |
|------|---------|
| `terraform/env/prod.tfvars` | Production variables (project, region, scaling) |
| `terraform/env/prod.backend.hcl` | GCS state bucket config (gitignored, copy from `.example`) |

To use a dev environment with separate state:

```bash
cp terraform/env/dev.backend.hcl.example terraform/env/dev.backend.hcl
terraform init -reconfigure -backend-config=env/dev.backend.hcl
terraform apply -var-file=env/dev.tfvars.example
```

## Smoke test endpoints

Once deployed, the service is reachable via the Load Balancer IP:

```bash
LB_IP=$(cd terraform && terraform output -raw load_balancer_ip)

curl http://$LB_IP/          # → Hello World
curl http://$LB_IP/healthz   # → ok
```

## Security controls

| Control | Tool | Where |
|---------|------|-------|
| Secret detection | `detect-private-key`, gitleaks | pre-commit |
| IaC misconfiguration | Checkov, TFLint | pre-commit |
| Container CVE scan | Trivy (HIGH/CRITICAL gate) | CI/CD (before deploy) |
| WAF / DDoS | Cloud Armor | GCP (Terraform managed) |
| Keyless CI auth | Workload Identity Federation | GitHub Actions |
| No direct pushes to main | `no-commit-to-branch` hook | pre-commit |
