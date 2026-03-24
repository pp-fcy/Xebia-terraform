# BUX DevOps Assignment – `what-time-is-it` on GCP

Infrastructure-as-Code repository for running
[`buxapp/what-time-is-it`](https://github.com/buxapp/what-time-is-it) on
Google Cloud Platform with:

- **Terraform** – all infrastructure defined as code
- **Cloud Run** – serverless containers in two regions (HA)
- **Global HTTPS Load Balancer** – anycast IP, TLS termination, geo routing
- **Cloud Armor** – WAF (OWASP CRS) + adaptive DDoS + rate limiting
- **GitHub Actions** – blue/green CI/CD with canary smoke tests

### Application container image

The **`Dockerfile`** builds the Kotlin app from the public assignment repo **[buxapp/what-time-is-it](https://github.com/buxapp/what-time-is-it)** (clone + `./mvnw package`), not from a pre-published base image.

**Use your fork** (after forking on GitHub):

```bash
docker build --build-arg APP_REPO=https://github.com/<your-user>/what-time-is-it.git .
# optional branch/tag:
docker build --build-arg APP_REPO=https://github.com/<your-user>/what-time-is-it.git --build-arg APP_REF=main .
```

In **GitHub Actions**, set optional repository **Variables**:

| Name | Purpose |
|------|--------|
| `APP_SOURCE_REPO` | e.g. `https://github.com/your-org/what-time-is-it.git` (defaults to `buxapp` if unset) |
| `APP_SOURCE_REF` | Branch or tag to build (leave empty for the repo default branch) |

If `./mvnw package` fails (e.g. legacy Maven repos), fork **[buxapp/what-time-is-it](https://github.com/buxapp/what-time-is-it)**, update `pom.xml` repositories if needed, and point `APP_SOURCE_REPO` at your fork.

### Trigger CI when the app repo changes (cross-repo)

`ci.yml` also listens for **`repository_dispatch`** with event type **`what-time-is-it-updated`**.

1. In **BUX-task** (this repo): no extra config — the workflow is already wired.
2. In **what-time-is-it** (your fork): add a **PAT** secret that can call `repository_dispatch` on BUX-task:
   - Classic PAT: **`repo`** scope (or fine-grained: access to the BUX-task repo with **Contents: Read** + **Metadata**; confirm PAT can hit the [repository dispatch API](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event)).
   - Secret name: **`BUX_TEST_DISPATCH_TOKEN`**
3. Copy **[`.github/workflows-examples/what-time-is-it-dispatch-bux-task.yml`](.github/workflows-examples/what-time-is-it-dispatch-bux-task.yml)** to the app repo as **`.github/workflows/dispatch-bux-task.yml`** and set **`repository:`** to your devops repo (e.g. `pp-fcy/BUX-task`).

On **push** to `main`/`master` in the app repo, that workflow notifies BUX-task. The CI job then clones **`client_payload.repository`** at **`client_payload.ref`**, so the image matches the commit that was pushed (set **`APP_SOURCE_REPO` / `APP_SOURCE_REF`** only for PR builds or when not using dispatch).

Production **`release.yml`** is still **manual** (`workflow_dispatch`) unless you add a separate dispatch trigger there.

---

## Architecture

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  Global External HTTPS Load Balancer  (static anycast IP) │
│  + Cloud Armor (WAF / DDoS / rate-limit)                  │
└──────────────┬───────────────────────────────┬───────────┘
               │                               │
     Serverless NEG                   Serverless NEG
               │                               │
   ┌───────────▼──────────┐       ┌────────────▼─────────┐
   │  Cloud Run           │       │  Cloud Run            │
   │  europe-west1        │       │  europe-west4         │
   │  (primary)           │       │  (secondary / HA)     │
   └──────────────────────┘       └───────────────────────┘
               │                               │
        Artifact Registry  ◄──── GitHub Actions (WIF, no keys)
```

Key design decisions:
- Cloud Run ingress is set to `INTERNAL_LOAD_BALANCER` – services are **not**
  directly reachable from the internet; all traffic flows through the LB and
  Cloud Armor.
- GitHub Actions authenticates via **Workload Identity Federation** (no
  long-lived service account keys stored in GitHub Secrets).
- Terraform fully owns the Cloud Run image. `container_image` is passed as
  `-var` on every apply so plan and state always reflect what is deployed.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Terraform | 1.5+ |
| gcloud CLI | 450+ |
| Docker | 20+ |

A GCP project with a billing account attached.

### Local checks (pre-commit)

Optional hooks run before each commit to keep Terraform and YAML consistent.

```bash
pip install -r requirements-dev.txt
pre-commit install

# One-time: TFLint Google plugin (required for terraform_tflint hook)
cd terraform && tflint --init && cd ..
```

Run all hooks manually:

```bash
pre-commit run --all-files
```

---

## Bootstrap (first-time setup)

### 1. Workload Identity Federation (GitHub Actions → GCP)

WIF is **project-level** identity setup (not in app Terraform). Run once per GCP project:

```bash
# Defaults are set in the script for this repo (bux-project-490819 + pp-fcy/BUX-task).
./scripts/bootstrap-wif.sh

# Or override:
# export GCP_PROJECT_ID="other-project"
# export GITHUB_REPO="org/other-repo"   # org/repo — not the full https://github.com/... URL
# ./scripts/bootstrap-wif.sh
```

The script prints `WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` values for GitHub Actions secrets (see [GitHub Repository Setup](#github-repository-setup)).

Optional overrides: `WIF_POOL_ID`, `WIF_PROVIDER_ID`, `GITHUB_ACTIONS_SA_ID`.

### 2. Terraform state bucket (GCS)

State lives in **one bucket** with **different prefixes per environment** (see `terraform/env/*.backend.hcl.example`). Root **`terraform/backend.tf`** only declares `backend "gcs" {}`; bucket/prefix come from those files at `terraform init`.

Example: **`gs://cfan-bux-tfstate`**, prefixes **`what-time-is-it/state`** (prod) and **`what-time-is-it/dev/state`** (dev).

If the bucket does not exist yet in your GCP org:

```bash
gsutil mb -l europe-west1 gs://cfan-bux-tfstate
gsutil versioning set on gs://cfan-bux-tfstate
```

### 3. Configure Terraform (production vs dev)

**`terraform/env/prod.tfvars`** and **`terraform/env/prod.backend.hcl`** are committed — no copying needed for production. CI/CD uses them directly.

**Production:**

```bash
./scripts/terraform-init-env.sh prod
cd terraform
terraform plan  -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```

**Dev (local sandbox, not used by CI/CD)** — copy the examples and edit with a different project/app_name to avoid clashing with prod:

```bash
cp terraform/env/dev.backend.hcl.example terraform/env/dev.backend.hcl   # edit bucket if needed
cp terraform/env/dev.tfvars.example       terraform/env/dev.tfvars         # edit project_id, app_name
./scripts/terraform-init-env.sh dev
cd terraform
terraform plan  -var-file=env/dev.tfvars
terraform apply -var-file=env/dev.tfvars
```

See **`terraform/env/README.md`**. Switching environments: run **`./scripts/terraform-init-env.sh prod`** or **`dev`** again (`-reconfigure`).

### 4. Apply

```bash
cd terraform
# After ./scripts/terraform-init-env.sh prod (or dev):
terraform plan  -var-file=env/prod.tfvars   # or env/dev.tfvars
terraform apply -var-file=env/prod.tfvars   # or env/dev.tfvars
```

Terraform will output:
- `load_balancer_ip` – point your DNS A-record here; set as `LB_HOSTNAME` GitHub variable in BUX-task
- `artifact_registry_url` – set as `ARTIFACT_REGISTRY_URL` in the **app repo's** GitHub variables (not BUX-task)

**Layout:** the app stack lives in **`terraform/modules/what-time-is-it/`**; root **`terraform/main.tf`** only calls `module "what_time_is_it"`.

WIF secrets (`WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`) come from `./scripts/bootstrap-wif.sh`, not Terraform.

---

## GitHub Repository Setup

### Variables (Settings → Secrets and variables → Actions → Variables)

Terraform config (regions, bucket, prefix) lives in committed files — no Terraform-specific variables needed. The only runtime variables BUX-task workflows use are:

| Name | Example value | Used by |
|------|--------------|---------|
| `GCP_PROJECT_ID` | `bux-project-490819` | `terraform.yml` (identity display) |
| `LB_HOSTNAME` | `34.x.x.x` or `time.example.com` | `release.yml` smoke test |

> **Docker image variables** (`ARTIFACT_REGISTRY_URL`, `GCP_REGION_PRIMARY`, `GCP_REGION_SECONDARY`, etc.) belong in the **app repo's** GitHub settings, not here. See the dispatch example workflow header for the full list.

### Secrets (Settings → Secrets and variables → Actions → Secrets)

| Name | How to get it |
|------|--------------|
| `WORKLOAD_IDENTITY_PROVIDER` | Output of `./scripts/bootstrap-wif.sh` (full provider resource name) |
| `GCP_SERVICE_ACCOUNT` | Output of `./scripts/bootstrap-wif.sh` (service account email) |

**Important**

- **Dependabot PRs** do **not** use repository Actions secrets by default. Add the **same secret names** under **Settings → Secrets and variables → Dependabot** (or the workflow cannot authenticate).
- **Pull requests from forks** never receive your repository secrets; the CI workflow that deploys to GCP is **skipped** for those PRs.
- **`release.yml`** jobs that use the **`production`** GitHub Environment must have these secrets available to that environment: add **`WORKLOAD_IDENTITY_PROVIDER`** and **`GCP_SERVICE_ACCOUNT`** under **Settings → Environments → `production` → Environment secrets** if repository secrets are not inherited as you expect.

### Verify GitHub Actions / Environment (CLI)

From your laptop (requires [GitHub CLI](https://cli.github.com/) and `gh auth login`):

```bash
./scripts/check-github-actions-environment.sh
# or
./scripts/check-github-actions-environment.sh pp-fcy/BUX-task
```

This lists **environment names**, **Actions variable names**, and **secret names** (values are never shown). It checks that `WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` exist either as **repository** secrets or on the **`production`** environment.

**One-liners** (same idea):

```bash
gh secret list -R pp-fcy/BUX-task
gh secret list -R pp-fcy/BUX-task --env production
gh api repos/pp-fcy/BUX-task/environments/production
```

**Create missing *repository* WIF secrets** (same values as `production` environment; uses `gcloud` + `gh`):

```bash
./scripts/set-github-repo-wif-secrets.sh
# or: GITHUB_REPO=pp-fcy/BUX-task GCP_PROJECT_ID=bux-project-490819 ./scripts/set-github-repo-wif-secrets.sh
```

**Manual `gh` one-liners** (paste your real values):

```bash
gh secret set WORKLOAD_IDENTITY_PROVIDER -R pp-fcy/BUX-task -b"projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider"
gh secret set GCP_SERVICE_ACCOUNT -R pp-fcy/BUX-task -b"github-actions-sa@bux-project-490819.iam.gserviceaccount.com"
```

---

## CI/CD Workflows

### On pull request (`ci.yml`)

```
PR opened / updated
  └─ Build Docker image (layer-cached)
  └─ Push to Artifact Registry with :sha and :pr-N tags
  └─ Deploy new revision with 0% traffic + tag `pr-<N>` (primary + secondary)
  └─ Smoke test the tagged preview URL
  └─ Post preview URL as PR comment
```

The new revision is live and testable but receives **zero production traffic**.

### On merge to main (`release.yml`)

```
Push to main
  └─ Re-tag image as :latest
  └─ (parallel) Primary region:
  │   └─ Deploy new revision, 0% traffic
  │   └─ Shift 10% → smoke test (10 requests via LB/Cloud Armor)
  │   └─ Shift 100% (promote)
  │   └─ Rollback to previous revision on any failure
  └─ (parallel) Secondary region:
      └─ Same flow, smoke test via direct Cloud Run URL
```

---

## Blue/Green Deployment Details

Cloud Run supports **traffic splitting natively**. Each `gcloud run deploy`
creates a new immutable revision. Traffic is shifted separately:

```
Revision A  (old – currently serving 100%)
Revision B  (new – just deployed with --no-traffic)

Canary phase:
  Revision A: 90% | Revision B: 10%

Promotion:
  Revision A: 0%  | Revision B: 100%  (--to-latest)
```

If the smoke test fails at 10%, the workflow's `on: failure` step runs:
```bash
gcloud run services update-traffic ... --to-revisions="<old>=100"
```
This restores the previous state within seconds.

---

## Security Highlights

| Control | Implementation |
|---------|---------------|
| Network perimeter | Cloud Run `INTERNAL_LOAD_BALANCER` ingress |
| WAF | Cloud Armor OWASP CRS (sqli, xss, lfi, rfi, rce, scanner) |
| DDoS | Cloud Armor adaptive protection (Layer 7) |
| Rate limiting | 100 req/min per IP; 5-min ban at 300 req/min |
| TLS | Google-managed certificate (auto-renewed) |
| CI/CD auth | Workload Identity Federation (no SA keys) |
| Runtime SA | Dedicated SA per Cloud Run service, no roles assigned by default |
| Image lifecycle | Artifact Registry retention: keep 10 latest, delete after 30 days |

---

## Cutting Corners (and how to fix them)

The following would be done with more time:

1. **No `terraform plan` in CI** – A proper setup posts the plan diff as a PR
   comment. Requires a GCS state bucket and WIF bootstrap (chicken-and-egg).

2. **No Checkov / tfsec** – Security scanning of Terraform would be added to
   the pre-commit / CI checks (e.g. `.pre-commit-config.yaml` / `pre-commit.yml`).

3. **No alerting** – Cloud Monitoring alerts on error rate/latency p99 should
   be wired to auto-trigger rollback via a Cloud Function or Pub/Sub.

4. **Secondary region HA behaviour** – The LB will route around an unhealthy
   backend automatically, but there is no explicit health check configuration
   beyond the default. Custom health check paths would make this more explicit.

5. **`min_instances = 1`** – Keeps the app warm to eliminate cold starts, but
   costs ~€5/month/region even at zero traffic. Setting to 0 in secondary
   and relying on the LB failover window is a valid cost trade-off.
