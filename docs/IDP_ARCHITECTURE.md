# Internal Developer Platform — Architecture

> Engineering-facing companion to the [Platform Operating Model](PLATFORM_OPERATING_MODEL.md).
> Walks through the IDP layers and the trade-offs we made to fit the 6-month
> deadline without painting ourselves into a corner for the longer-term GKE +
> Istio target architecture in the management summary.

## The five layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│  L5  Developer Experience    GitHub repo template · README onboarding    │
│      (what the dev sees)      Pre-commit hooks · service-team < 2h path  │
├──────────────────────────────────────────────────────────────────────────┤
│  L4  Delivery & Promotion     GitHub Actions reusable workflows          │
│      (CI/CD)                  pre-commit → terraform plan/apply          │
│                               → Cloud Build → deploy + smoke test        │
├──────────────────────────────────────────────────────────────────────────┤
│  L3  Self-Service Resources   Terraform module registry                  │
│      (golden-path infra)      modules/what-time-is-it (compute)          │
│                               modules/observability (golden monitoring)  │
├──────────────────────────────────────────────────────────────────────────┤
│  L2  Platform Primitives      Cloud Run · Artifact Registry · GCS state  │
│      (managed by platform)    Global LB · Cloud Armor · Cloud Monitoring │
│                               Workload Identity Federation               │
├──────────────────────────────────────────────────────────────────────────┤
│  L1  Identity & Compliance    Workload Identity (no SA keys)             │
│      (security baseline)      Cloud Armor (OWASP CRS, rate limiting)     │
│                               IAM least-privilege per Cloud Run service  │
└──────────────────────────────────────────────────────────────────────────┘
```

This repo concretely implements **L1–L5** for one sample service. Adding the
next service is "copy the composition, change `app_name`."

## What's in this repo, mapped to the assignment's "walking stick"

The assignment requires four components. Here is exactly where each one lives:

| Walking-stick requirement | Where in the repo | One-line description |
|---------------------------|-------------------|----------------------|
| **One sample service in a repo** | [`hello-world/`](../hello-world/) | Hello World HTTP server (stdlib Python, returns `Hello World` on `/` and `ok` on `/healthz`), Dockerfile. |
| **IaC of a basic cloud resource** | [`terraform/`](../terraform/) | Cloud Run, Artifact Registry, Global LB, Cloud Armor, observability. |
| **Automated pipeline that deploys on push** | [`.github/workflows/`](../.github/workflows/) | `pre-commit` → `terraform plan/apply` → `build-image` (Cloud Build) → deploy + smoke test. |
| **Simple observability setup** | [`terraform/modules/observability/`](../terraform/modules/observability/) | Dashboard, log-based error metric, uptime check, alert policy — all IaC. |

## End-to-end runtime

```
                                    DEVELOPER
                                       │
                                       │ git push
                                       ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ GitHub Actions (Workload Identity Federation, no static creds)             │
│                                                                             │
│  pre-commit (gate) ──► terraform plan/apply (infra) ──► build-image        │
│                                                          (Cloud Build)      │
│                                                                  │          │
│                                                                  ▼          │
│                                                        deploy (terraform.yml) │
│                                                        ├─ terraform apply   │
│                                                        │  with new image    │
│                                                        └─ smoke test        │
│                                                           (/, /healthz)     │
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
              │  Cloud Monitoring                              │
              │  ├─ Service dashboard (req/s, latency, errors) │
              │  ├─ Log-based metric: app_errors               │
              │  ├─ Uptime check (LB)                          │
              │  └─ Alert policies → email                     │
              └────────────────────────────────────────────────┘
```

> **Single-region simple POC.** No canary, no blue/green, no auto-rollback,
> no manual `workflow_dispatch`. The deploy is one `terraform apply` with the
> freshly built image followed by a smoke test; rollback is a revert commit
> (re-runs the same pipeline) or a Cloud Run console revision swap as an
> emergency lever. Adding HA / progressive delivery is a focused module +
> workflow change for the launch-readiness phase.

## Trade-offs we made (and why)

### 1. Cloud Run today, GKE/Istio later

The management summary's target architecture is **shared GKE + Istio + ArgoCD**
because that scales to multi-tenant SaaS economics. The walking stick is on
**Cloud Run** because:

- A simple single-region apply + smoke-test pipeline ships in days, not weeks.
- It exercises every IDP idea (IaC, golden paths, automated delivery,
  observability) at a fraction of the build cost.
- The Terraform module boundary is the seam: replacing the contents of
  `modules/what-time-is-it/` with a Helm chart + ArgoCD `Application` is a
  drop-in change for product teams. They keep calling `module "service" { ... }`.

This is consciously a "buy time, decide later" trade. The assignment explicitly
says **don't over-engineer**.

### 2. GitHub repo template + Actions, no portal yet

The L5 developer experience today is **just GitHub**: this repo is marked as a
template, and a developer's path to a new service is `Use this template → edit
prod.tfvars → push`. No portal, no scaffolder, no service catalog to operate.

That cuts a lot of platform-team work for the 6-month launch. A portal
(Backstage or similar) is a post-launch addition once there are enough services
to make discoverability the bottleneck. See
[SERVICE_TEMPLATE.md](SERVICE_TEMPLATE.md) for the actual onboarding flow.

### 3. Observability is GCP-native, not Prometheus + Grafana

Cloud Monitoring + Cloud Logging cover the management summary's "unified
dashboards, logs, metrics, traces" requirement at zero standing-cost. Pivoting
to Managed Prometheus + Grafana later is purely an `observability` module
change — product team Terraform composition does not change.

### 4. Single-tenant in the demo, multi-tenant in the roadmap

The walking stick deliberately keeps the **single-tenant** topology so the
deploy story stays simple to present in 30 minutes. The Phase 03 multi-tenant
migration is documented in the management summary (Wks 11–16) but **not in the
demo** — confusing the audience by introducing namespaces + Istio in a Cloud
Run demo would weaken the central message: *the platform shape works*.

## Cost model (rough order of magnitude)

| Resource | Monthly cost @ launch traffic | Notes |
|----------|-------------------------------|-------|
| Cloud Run (single region) | ~€5–10 | `min_instances = 1` eliminates cold starts. Set to 0 to save €5/mo at the cost of cold-start latency on first request after idle. |
| Global LB | ~€18 | Forwarding rule + processed bytes. Same regardless of service count. |
| Cloud Armor | ~€5 + €0.75/M requests | Shared across services in production. |
| Artifact Registry | < €1 with cleanup policy (keep 10) | Cleanup policy already in `modules/what-time-is-it/main.tf`. |
| Cloud Monitoring + dashboard | Free at this scale | Only metric streams above the free tier are billed. |
| Cloud Build | Pay-per-build, ~€0.003/minute | One build per push; ~3 minutes per build. |

Order-of-magnitude bill for one service at launch: **< €50/month**. The 40%
cost reduction goal in the management summary comes from the multi-tenant
migration in Phase 03 (collapsing per-tenant clusters), not from this service's
footprint.

## What is intentionally not in the walking stick

| Cut | Why | When we add it back |
|-----|-----|---------------------|
| Multi-region HA (second Cloud Run + extra LB backend) | Walking stick is a simple POC — adds module complexity and cost without changing the platform shape | Launch-readiness phase, ahead of go-live |
| Canary / blue-green / progressive delivery | Out of scope for the POC. Smoke test on the new revision plus manual rollback to a prior image is enough to demonstrate safe delivery | When traffic + revenue justify the extra workflow complexity |
| Multi-tenant isolation | Cloud Run is single-tenant by design; demo would need GKE | Phase 03, weeks 11–16 |
| Distributed tracing (OTel + Cloud Trace) | App-side instrumentation requires a code change | Sprint after foundation, post-launch |
| Policy-as-code (Checkov / OPA) | Listed in README "Cutting Corners" — fits naturally as a pre-commit hook | Phase 02, week 7 |
| FinOps / per-tenant cost attribution | Needs a billing-export → BigQuery setup | Phase 02, weeks 7–10 |
| Service catalog / portal (Backstage or similar) | Out of scope — golden path today is just GitHub CI/CD | Post-launch when there are 5+ services to discover |
