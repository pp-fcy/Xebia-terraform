# Service Template — The Golden Path

> Walks a developer (or platform team) from **zero to first deploy in under 2 hours**
> by reusing this repo as a GitHub template. This is the management summary's
> "New service launch in < 2 hrs — zero tickets" promise made concrete.

## How the template works

This whole repo doubles as a GitHub repo template. Mark it as a template under
**Settings → General → Template repository**. From then on every developer can
spin up a new service via:

```
GitHub  →  "Use this template"  →  Create your repo
                                       │
                                       ▼
              Run ./scripts/init-project.sh once
                                       │
                                       ▼
                       Push to main → CI deploys
```

No tickets. No Slack DMs to Cloud Engineering.

## The 8-step golden path (target: < 2 hours wall-clock)

Each step is small enough to fit on a single PR.

| # | Step | Where | Time |
|---|------|-------|------|
| 1 | Click **Use this template** on GitHub | github.com | 1 min |
| 2 | Rename `hello-world/` (the sample-service dir) to your service name | local clone | 2 min |
| 3 | Update `terraform/env/prod.tfvars` (`project_id`, `app_name`, region) | editor | 2 min |
| 4 | Drop your code into your service directory (replace `server.py` + `Dockerfile`) | editor | varies |
| 5 | Adjust `Dockerfile` if your stack differs (Python/Node/Go templates can be added later) | editor | 5 min |
| 6 | Run `./scripts/init-project.sh` to bootstrap WIF + GCS state bucket | terminal | 10 min |
| 7 | Push to `main` — pipeline runs automatically | git | < 1 min |
| 8 | Open the **dashboard URL** from `terraform output` to confirm health | browser | < 1 min |

**Total**: ~25 min of clicks/edits + ~1 hour of pipeline runs (Cloud Build,
Terraform apply, deploy + smoke test) = first request answered in < 2 hours.

## What the template gives you for free

Everything in the [IDP architecture map](IDP_ARCHITECTURE.md#the-five-layers):

- **L1 Identity & Compliance**
  - Workload Identity Federation — no static cloud credentials in GitHub
  - Cloud Armor with OWASP CRS rules + rate limiting
  - Per-service Cloud Run service account
- **L2 Platform Primitives**
  - Cloud Run (single region), behind a Global Load Balancer
  - Artifact Registry with cleanup policy (keep 10 images, delete > 30 days)
- **L3 Self-Service Resources**
  - `modules/what-time-is-it/` — replace the contents, keep the seam
  - `modules/observability/` — drop in for any service, no edits
- **L4 Delivery & Promotion**
  - `pre-commit` workflow (terraform fmt, validate, file hygiene)
  - `terraform.yml` (plan posted as PR comment, apply on merge, reusable deploy job)
  - `build-image.yml` (Cloud Build with layer cache → calls the deploy job with the new image)
  - Deploy = `terraform apply` + smoke test on `/` and `/healthz`. Manual `workflow_dispatch` of the deploy job with a previous image is the rollback path.
- **L5 Developer Experience**
  - This documentation
  - Service-level README in `hello-world/`
  - The repo itself, marked as a **GitHub template repository**

## Why "GitHub repo template" is the whole golden path

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **GitHub template repo** (this) | Native to GitHub, zero new infra to operate, every developer already knows the button | Manual rename of `hello-world/` → service name (and the `^hello-world/` path filter in `build-image.yml`) | **Picked.** Cheapest, fastest. The golden path *is* this repo plus its CI/CD. |
| Cookiecutter + script | Templating engine handles renames automatically | Requires Python locally; one more thing for the platform team to maintain | Defer to Phase 02 if pain emerges |
| Service catalog / portal (Backstage or similar) | Best UX (form-driven), supports policy gating | Need a running portal first; not in 6-month scope for this team | Post-launch, when there are 5+ services and discovery is the bottleneck |

The template-repo approach buys us the right thing now (every team can
self-serve) without operating a portal in addition to the platform itself.

## When the golden path doesn't fit

The promise is **the 80% case**. Edge cases (a workload that needs GPU, a
service that has to live in `us-central1` for data-residency, a request to
disable Cloud Armor for a partner integration) go through the **Architecture
Review Board** and may result in a *new* golden path being added — not a
one-off bypass. See the bypass policy in
[PLATFORM_OPERATING_MODEL.md](PLATFORM_OPERATING_MODEL.md#golden-path-principle).

## Demo: the 2-hour clock

The 30-minute presentation includes a live walk of steps 1–4 plus a pre-baked
push to demonstrate the pipeline. See [DEMO_SCRIPT.md](DEMO_SCRIPT.md).
