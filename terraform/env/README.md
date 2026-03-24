# Terraform environments

Environment-specific config lives in this directory (`terraform/env/`).

| File | Purpose | Committed? |
|------|---------|-----------|
| `prod.tfvars` | Production variable values | ✅ Yes |
| `prod.backend.hcl` | Production GCS state bucket/prefix | ✅ Yes |
| `dev.tfvars.example` | Dev template — copy and edit locally | ✅ Yes (example only) |
| `dev.backend.hcl.example` | Dev backend template — copy and edit locally | ✅ Yes (example only) |

Production files are committed so CI/CD can use them directly (`-var-file=env/prod.tfvars`, `-backend-config=env/prod.backend.hcl`).

Dev files are examples only — copy them for a local sandbox environment:

```bash
cd terraform/
cp env/dev.tfvars.example  env/dev.tfvars    # edit: set project_id, app_name, etc.
cp env/dev.backend.hcl.example env/dev.backend.hcl  # edit if bucket differs
terraform init -backend-config=env/dev.backend.hcl
terraform plan  -var-file=env/dev.tfvars
terraform apply -var-file=env/dev.tfvars
```

Each environment uses its **own GCS state prefix** so dev and prod state never mix.

## container_image

`container_image` is **not** set in either tfvars file. CI/CD always passes it as a `-var` flag:

```bash
# CI/CD (release.yml / terraform.yml)
terraform apply -var-file=env/prod.tfvars -var="container_image=<registry>/<name>:<sha>"

# Local — pass explicitly or rely on the hello-world default for bootstrap
terraform apply -var-file=env/dev.tfvars -var="container_image=us-docker.pkg.dev/..."
```

## Switching environments

```bash
cd terraform/
terraform init -reconfigure -backend-config=env/prod.backend.hcl   # prod
terraform init -reconfigure -backend-config=env/dev.backend.hcl    # dev
# or use the helper:
../scripts/terraform-init-env.sh prod   # or dev
```
