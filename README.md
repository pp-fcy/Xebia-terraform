# FinCore IDP — Walking-Stick Demo

> Xebia Platform Architect Assessment · Chaoyang Fan · 2026
>
> **Audience:** VP of Engineering · Senior Cloud Engineer
> **Companion docs:** [Management Summary](#management-summary) · [Platform Operating Model](docs/PLATFORM_OPERATING_MODEL.md) · [IDP Architecture](docs/IDP_ARCHITECTURE.md) · [Service Template / Golden Path](docs/SERVICE_TEMPLATE.md) · [30-min Demo Script](docs/DEMO_SCRIPT.md)

A working **Internal Developer Platform** demo for the FinCore Systems
Platform Architect assessment. The repo doubles as **(a)** the platform
golden-path service template and **(b)** a sample service consuming the
golden path end-to-end on Google Cloud.

The four "walking stick" requirements from the assignment are all live:

| Requirement | Where it lives in this repo |
|---|---|
| One sample service in a repo | [`hello-world/`](hello-world/) — minimal Hello World HTTP server (stdlib Python, returns `Hello World` on `/` and `ok` on `/healthz`) |
| Infra-as-Code provisioning of a basic cloud resource | [`terraform/`](terraform/) — Cloud Run, Artifact Registry, Global LB, Cloud Armor |
| Automated pipeline that deploys on push | [`.github/workflows/`](.github/workflows/) — pre-commit → terraform plan/apply → build → deploy + smoke test |
| Simple observability setup | [`terraform/modules/observability/`](terraform/modules/observability/) — dashboard, log-based error metric, uptime check, alert policy |

---

## Management Summary

**Situation.** FinCore Systems must launch its SaaS platform in 6 months to
avoid permanent loss of market trust. 17 product teams are stalled by a
**Gatekeeper model** — every infra change requires manual Cloud Engineering
intervention. Slow delivery, fragile deployments, no self-service,
uncontrolled cloud costs.

**Proposal.** Transform Cloud Engineering from manual bottleneck into an
**Enabling Platform Team** that builds and maintains an Internal Developer
Platform. The 17 product teams operate as autonomous, stream-aligned
consumers of golden paths — self-serving without sacrificing security,
stability, or observability.

**This repo demonstrates Phase 01 (Foundation) of that plan.**

| Outcome | Today (Gatekeeper) | After Phase 01 (this demo) |
|---------|---------------------|---------------------------|
| Deployment frequency | 1× per sprint | Daily, on push |
| Lead time for change | ~5 days | < 1 day |
| New service to first deploy | ~3 days of tickets | < 2 hours, zero tickets |
| Observability shape | Per-team, ad-hoc | Identical golden-path dashboard per service |
| Cloud creds in CI | Static SA keys | Workload Identity Federation, no static creds |
| Smoke test on every release | None | Built into the deploy job (`/` and `/healthz` checks; failed test fails the run) |

The 6-month roadmap, success metrics, and 40% cost reduction story (multi-tenant
migration in Phase 03) are in the separate
[Management Summary PDF](https://github.com/pp-fcy/BUX-task) delivered
24 hours before the presentation per the assignment.

---

## How to read this repo

Three audiences, three reading orders:

**For the VP of Engineering** (you):
1. This README's [Management Summary](#management-summary) above.
2. [docs/PLATFORM_OPERATING_MODEL.md](docs/PLATFORM_OPERATING_MODEL.md) — RACI, Team Topologies, success metrics.
3. [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) — what the 30 minutes will look like.

**For the Senior Cloud Engineer**:
1. [docs/IDP_ARCHITECTURE.md](docs/IDP_ARCHITECTURE.md) — 5-layer IDP map, runtime diagram, trade-offs.
2. [terraform/modules/observability/README.md](terraform/modules/observability/README.md) — the observability golden path.
3. [.github/workflows/](.github/workflows/) — the actual pipelines.

**For a product-team developer onboarding** (the future state):
1. [docs/SERVICE_TEMPLATE.md](docs/SERVICE_TEMPLATE.md) — 9 steps, < 2 hours to first deploy.
2. The [Bootstrap](#bootstrap-first-time-setup) section below.

---

## Architecture (one picture)

```
                            DEVELOPER (product team)
                                       │
                                       │ git push
                                       ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ GitHub Actions (Workload Identity Federation, no static creds)             │
│                                                                             │
│   pre-commit ──► terraform plan/apply ──► build (Cloud Build) ──► deploy   │
│                                                                  │          │
│                                                       terraform apply       │
│                                                       + smoke test (/, /healthz) │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
                ┌────────────────────────────────────────────┐
                │   Global HTTPS LB (anycast IP)             │
                │   + Cloud Armor (OWASP CRS, rate limiting) │
                └────────────────────┬───────────────────────┘
                                     │
                          ┌──────────▼─────────┐
                          │  Cloud Run         │
                          │  europe-west1      │
                          └──────────┬─────────┘
                                     │ logs · metrics
                                     ▼
              ┌────────────────────────────────────────────────┐
              │  Cloud Monitoring — golden-path observability  │
              │  Dashboard · Log-based metric · Uptime · Alert │
              └────────────────────────────────────────────────┘
```

> Single-region by design. The walking stick is a **simple POC** — adding HA
> (a second Cloud Run + extra NEG + LB backend) is a focused module change
> the platform team can ship in one sprint when the launch readiness phase
> needs it. See [IDP_ARCHITECTURE.md](docs/IDP_ARCHITECTURE.md#trade-offs).

Detailed 5-layer IDP map and trade-offs in
[docs/IDP_ARCHITECTURE.md](docs/IDP_ARCHITECTURE.md).

---

## Why Cloud Run for the walking stick (and not GKE)

The management summary describes a future-state on **shared GKE + Istio +
ArgoCD** with Kubernetes namespaces for tenant isolation. The walking stick
is on **Cloud Run** because:

- It exercises every IDP idea (IaC, golden paths, automated promotion, observability) at a fraction of the build cost.
- A simple deploy + smoke-test pipeline ships in days, not weeks.
- The Terraform module boundary is the seam: replacing the contents of `modules/what-time-is-it/` with a Helm chart + ArgoCD `Application` is a drop-in change. Product teams keep calling `module "service" { ... }`.

This is consciously a "buy time, decide later" trade. The assignment explicitly
says **don't over-engineer the demo**.

---

## Application container image

The **`Dockerfile`** in [`hello-world/`](hello-world/) is a single-stage
`python:3.12-alpine` image that runs the stdlib HTTP server in
[`server.py`](hello-world/server.py). No upstream repo, no Maven build, no app
dependencies — kept deliberately small so the demo's attention stays on the
platform (pipeline, IaC, observability) rather than on the workload.

```bash
# Build and run locally
docker build -t hello-world hello-world/
docker run --rm -p 8080:8080 hello-world
curl http://localhost:8080/         # → Hello World
curl http://localhost:8080/healthz  # → ok

# Override the response without rebuilding (env vars in server.py)
docker run --rm -p 8080:8080 -e HELLO_MESSAGE="Bonjour FinCore" hello-world
```

A product team that adopts this template replaces `server.py` and `Dockerfile`
with their real workload and inherits the rest of the platform unchanged.

### Optional: build on push from a separate app repo

`build-image.yml` also listens for **`repository_dispatch`** with event type
**`hello-world-updated`** so a product team can keep their service code in
its own repo and have this platform repo build/deploy it on each push. Wire
the dispatch using the example workflow at
[`.github/workflows-examples/`](.github/workflows-examples/). For the
walking-stick demo this is unused — the sample service lives in this same repo.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Terraform | 1.5+ |
| gcloud CLI | 450+ |
| Docker | 20+ |

A GCP project with a billing account attached.

### Local checks (pre-commit)

```bash
pip install -r requirements-dev.txt
pre-commit install
cd terraform && tflint --init && cd ..
pre-commit run --all-files
```

---

## Bootstrap (first-time setup)

### 1. Workload Identity Federation (GitHub Actions → GCP)

WIF is **project-level** identity setup (not in app Terraform). Run once per GCP project:

```bash
# Defaults are set in the script for this repo (bux-project-490819 + pp-fcy/BUX-task).
./scripts/init-project.sh

# Or override:
# export GCP_PROJECT_ID="other-project"
# export GITHUB_REPO="org/other-repo"
# ./scripts/init-project.sh
```

The script prints `WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` values
for GitHub Actions secrets.

### 2. Terraform state bucket (GCS)

State lives in **one bucket** with **different prefixes per environment** (see
`terraform/env/*.backend.hcl.example`). Root **`terraform/backend.tf`** only
declares `backend "gcs" {}`; bucket/prefix come from those files at
`terraform init`.

Example: **`gs://cfan-bux-tfstate`**, prefixes **`what-time-is-it/state`** (prod)
and **`what-time-is-it/dev/state`** (dev).

If the bucket does not exist yet:

```bash
gsutil mb -l europe-west1 gs://cfan-bux-tfstate
gsutil versioning set on gs://cfan-bux-tfstate
```

### 3. Configure Terraform (production vs dev)

**`terraform/env/prod.tfvars`** and **`terraform/env/prod.backend.hcl`** are
committed — no copying needed for production. CI/CD uses them directly.

**Production:**

```bash
./scripts/terraform-init-env.sh prod
cd terraform
terraform plan  -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```

**Dev (local sandbox)** — copy the examples and edit with a different project:

```bash
cp terraform/env/dev.backend.hcl.example terraform/env/dev.backend.hcl
cp terraform/env/dev.tfvars.example       terraform/env/dev.tfvars
./scripts/terraform-init-env.sh dev
cd terraform
terraform plan  -var-file=env/dev.tfvars
terraform apply -var-file=env/dev.tfvars
```

### 4. Apply

```bash
cd terraform
terraform plan  -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```

Terraform outputs:
- `load_balancer_ip` — point your DNS A-record here
- `dashboard_url` — direct console URL for the **service overview dashboard** (open this in the demo)
- `artifact_registry_url` — set as `ARTIFACT_REGISTRY_URL` in the **app repo's** GitHub variables

**Layout:**

```
terraform/
├── main.tf                   # composes the two modules below
├── modules/
│   ├── what-time-is-it/      # service stack (Cloud Run, LB, Armor, AR)
│   └── observability/        # golden-path observability (NEW)
└── env/                      # backend + tfvars per environment
```

WIF secrets (`WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`) come from
`./scripts/init-project.sh`, not Terraform.

---

## GitHub Repository Setup

### Variables (Settings → Secrets and variables → Actions → Variables)

| Name | Example value | Used by |
|------|--------------|---------|
| `GCP_PROJECT_ID` | `bux-project-490819` | `terraform.yml` (identity display) |
| `LB_HOSTNAME` | `34.x.x.x` or `time.example.com` | Optional — point your DNS at this if you set a custom domain |

Docker image variables (`ARTIFACT_REGISTRY_URL`, `GCP_REGION_PRIMARY`) belong
in the **app repo's** GitHub settings if you split repos, not here.

### Secrets

| Name | How to get it |
|------|--------------|
| `WORKLOAD_IDENTITY_PROVIDER` | Output of `./scripts/init-project.sh` |
| `GCP_SERVICE_ACCOUNT` | Output of `./scripts/init-project.sh` |

**Important**

- **Dependabot PRs** do not use repository Actions secrets by default. Add the same secret names under **Settings → Secrets and variables → Dependabot**.
- **Pull requests from forks** never receive your repository secrets; the deploy workflow is **skipped** for those PRs.
- The `apply` and `deploy` jobs in **`terraform.yml`** use the **`production`** GitHub Environment — make sure the WIF secrets are available there (or are inherited from repository secrets).

---

## CI/CD Workflows — the IDP delivery layer

Three workflows in `.github/workflows/` are the platform team's contribution
to every product team's repo. A product team using the template inherits them
unchanged.

### On pull request

```
PR opened / updated
  └─ pre-commit  (terraform fmt/validate, file hygiene)
  └─ terraform plan  (gated on pre-commit; posts diff as PR comment)
```

### On push to main

```
push to main
  ├─ pre-commit
  ├─ terraform apply (only if terraform/ files changed, image preserved from state)
  └─ build-image  (only if hello-world/ files changed; Cloud Build, layer-cached)
       ├─ build  (Cloud Build → push to Artifact Registry)
       └─ deploy (terraform apply with the new image, then smoke-test)
            ├─ smoke test:  GET / → "Hello World",  GET /healthz → "ok"
            └─ smoke-test failure fails the run; rollback = push a revert
               commit (re-runs the same pipeline) or roll back the Cloud Run
               revision in the GCP console as an emergency lever
```

> **No manual `workflow_dispatch`.** Every code path goes through Pre-commit
> first; there are no escape hatches in CI. This keeps the platform's
> "one supported way to ship a service" promise honest.

The `pre-commit` workflow is the **hard gate** — `terraform.yml` and
`build-image.yml` both fire via `workflow_run` only after it succeeds.

### Concurrency

`terraform.yml` and `build-image.yml` share the `terraform-production`
concurrency group so no two `terraform apply` runs touch state in parallel.
Build-image's deploy job is **inline** (not a reusable `workflow_call`) —
keeping it inline avoids the dual-trigger `inputs` context pitfall in GitHub
Actions that previously caused "Startup failure" on `workflow_run` triggers.

---

## Observability — the golden path

`terraform/modules/observability/` is the most reusable part of the platform.
Drop-in for any service:

```hcl
module "observability" {
  source = "./modules/observability"

  project_id     = var.project_id
  app_name       = var.app_name
  primary_region = var.primary_region
  uptime_check_host = module.what_time_is_it.load_balancer_ip
  alert_notification_emails = ["platform-oncall@fincore.example"]
}
```

Provisions:
- **Cloud Monitoring dashboard** (`dashboard_url` output) — req/s, instance count, p50/p95/p99 latency, 5xx rate, error log rate.
- **Log-based metric** counting `severity>=ERROR` Cloud Run log entries.
- **Uptime check** against the LB.
- **Alert policies** for high error rate and uptime failure, optionally wired to email channels.

Same module, same shape, every service. On-call rotates without retraining.
See [terraform/modules/observability/README.md](terraform/modules/observability/README.md).

---

## Security highlights

| Control | Implementation |
|---------|---------------|
| Network perimeter | Cloud Run `INTERNAL_LOAD_BALANCER` ingress |
| WAF | Cloud Armor OWASP CRS (sqli, xss, lfi, rfi, rce, scanner) |
| DDoS | Cloud Armor adaptive protection (Layer 7) |
| Rate limiting | 100 req/min per IP; 5-min ban at 300 req/min |
| TLS | Google-managed certificate (auto-renewed) |
| CI/CD auth | Workload Identity Federation — no SA keys |
| Runtime SA | Dedicated SA per Cloud Run service, no roles by default |
| Image lifecycle | Artifact Registry retention: keep 10 latest, delete after 30 days |

---

## What we cut from the walking stick (and when we add it back)

The assignment says **don't over-engineer**. These are the intentional cuts:

| Cut | Why | When |
|-----|-----|------|
| Multi-region HA (second Cloud Run + extra LB backend) | Walking stick is a simple POC — adding a second region is a focused module change, not a platform redesign | Launch-readiness phase, ahead of go-live |
| Canary / blue-green / progressive delivery | Out of scope for the POC. Smoke test on the new revision + revert-commit rollback (or console-side Cloud Run revision rollback) is enough to demo safe delivery | When traffic + revenue justify the operational overhead |
| Multi-tenant isolation (GKE + Istio namespaces) | Cloud Run is single-tenant by design | Phase 03, weeks 11–16 |
| Distributed tracing (OTel + Cloud Trace) | App-side instrumentation is a code change | Sprint after Foundation |
| Policy-as-code (Checkov / OPA) | Fits as a pre-commit hook | Phase 02, week 7 |
| FinOps / per-tenant cost attribution | Needs billing-export → BigQuery | Phase 02, weeks 7–10 |
| Service catalog / portal (Backstage or similar) | Out of scope — the golden path today is just GitHub CI/CD | Post-launch when there are >5 services and discoverability matters |
| `terraform plan` posted as PR comment for the observability module | Separate state would require its own bucket prefix | Trivial extension; single state today keeps demo simple |

Everything cut is documented somewhere (this section, `docs/IDP_ARCHITECTURE.md`,
the management summary roadmap). Nothing is silently missing.
