# 30-minute Demo Script

> Audience: **VP of Engineering** + **Senior Cloud Engineer** at FinCore.
> Hardware: beamer + HDMI (per the assignment).
> Goal: convince them the **walking-stick IDP** is real, the operating model is
> sound, and the 6-month deadline is achievable.
>
> Time budget excludes Q&A (per assignment).

## Setup before the room

- [ ] Browser tabs open in this order: GitHub repo, Cloud Run console,
  Cloud Monitoring dashboard URL (`terraform output dashboard_url`),
  GitHub Actions runs page.
- [ ] Terminal pre-positioned in the repo root, last command being
  `terraform output` so the LB IP and dashboard URL are on screen.
- [ ] One pre-prepared branch (`demo/change-text`) with a tiny code change ready
  to push live.
- [ ] One previous successful image tag noted down — if the live deploy fails,
  swap the Cloud Run revision in the GCP console (or push a revert commit and
  let the same pipeline redeploy the prior code) as the rollback path.
- [ ] [Management Summary](../README.md#management-summary) printed copies on
  the table.

## Time budget

| Segment | Time | Slot in deck |
|---------|------|--------------|
| 0 — Frame the problem | 2 min | Slide 1–2 |
| 1 — Platform Operating Model | 4 min | Slide 3–4 |
| 2 — IDP architecture | 4 min | Slide 5 |
| 3 — Live demo | 14 min | Slide 6 (live) |
| 4 — Roadmap & success metrics | 4 min | Slide 7–8 |
| 5 — Wrap & ask | 2 min | Slide 9 |
| **Total** | **30 min** | |

Buffer: 0 minutes. Tight on purpose. Q&A is separate.

## Segment 0 — Frame the problem (2 min)

> "FinCore has a 6-month deadline, 17 product teams, and a Cloud Engineering
> team that is the bottleneck on every release. I'm going to show you the
> platform shape that gets you to launch, the operating model behind it, and
> a working walking-stick demo that proves it."

**Read** the four red boxes from the management summary aloud (slow delivery,
fragile deployments, no self-service, uncontrolled cost). Don't editorialise.

## Segment 1 — Platform Operating Model (4 min)

Three points, one per minute.

1. **Cloud Engineering becomes the Platform Team.** Not "fewer responsibilities" —
   *different* responsibilities. They build the IDP that the 17 product teams
   consume. Reference: [Platform Operating Model](PLATFORM_OPERATING_MODEL.md).
2. **There is one supported way to ship a service.** Bypass requests are
   declined, not negotiated. Show the RACI table on the slide.
3. **Stream-aligned product teams own production.** Their on-call, their SLOs,
   their cost. The Platform Team owns the pipeline that lets them do it.

End on the Team Topologies sentence:
> "1 Platform Team enabling 17 stream-aligned teams. 1 Security and 1 QA
> as transient enabling teams."

## Segment 2 — IDP Architecture (4 min)

Open [IDP_ARCHITECTURE.md](IDP_ARCHITECTURE.md) on the beamer for 30 seconds —
show the **5-layer stack** (Identity → Primitives → Self-service → Delivery →
DevEx). Don't read it; use it to anchor the next 3 minutes.

Walk the four assignment requirements on screen:

| What the assignment asked for | Where it lives |
|-------------------------------|----------------|
| Sample service in a repo | `hello-world/` (stdlib Python) |
| IaC of a basic cloud resource | `terraform/modules/what-time-is-it/` |
| Automated pipeline that deploys on push | `.github/workflows/` (4 workflows) |
| Simple observability | `terraform/modules/observability/` |

End with the trade-off: **Cloud Run today, GKE/Istio later**. The seam is the
Terraform module — product teams keep calling `module "service"`, the contents
swap. *Do not over-engineer the demo.*

## Segment 3 — Live demo (14 min) — **the heart of the talk**

Five sub-segments, each ≤ 3 min so you can drop one if you fall behind.

### 3a — The repo as a service template (3 min)

- Show GitHub UI: **Settings → Template repository** (toggled on).
- Click **Use this template** to demonstrate a developer's path.
  - Don't actually create the new repo — just show the dialog and close it.
- Open `docs/SERVICE_TEMPLATE.md`. *"Eight steps, 25 minutes of clicks, < 2 hours
  to first prod request. The golden path is just this template plus its CI/CD —
  no portal, no scaffolder to operate."*
- Open `hello-world/server.py` and `Dockerfile`. *"Sample service is
  deliberately tiny — Hello World in stdlib Python. A product team replaces
  these two files with their real workload and inherits everything else for
  free."*

### 3b — Code → CI on push (3 min)

In the terminal:

```bash
git checkout demo/change-text
# show the diff — one-line change in the Hello World server
git diff main -- hello-world/server.py
git push origin HEAD:main
```

Switch to the **GitHub Actions** tab. Walk the workflow chain on the live run:

1. `pre-commit` — terraform fmt + validate, file hygiene.
2. `terraform plan` (skipped — no infra changes; note the gate works).
3. `build-image` — Cloud Build, layer-cached.
4. `deploy` (called from `build-image.yml`) — `terraform apply` with the new
   image, then smoke test `/` returns "Hello World" and `/healthz` returns "ok".

> "No tickets. No DM to Cloud Engineering. Workload Identity Federation, no SA
> keys in GitHub. Pre-commit is a hard gate before anything touches prod. The
> deploy is single-region, no canary — that's deliberate for the POC. Adding
> progressive delivery is a focused workflow change once the platform is live."

### 3c — IaC self-service (2 min)

Open `terraform/main.tf` in the browser (root composition):

```hcl
module "what_time_is_it" { ... }    # the service
module "observability"   { ... }    # the golden-path observability
```

> "Two modules. Adding a second service is the same shape: copy this composition,
> change `app_name`. The platform team maintains the module; the product team
> instantiates it."

Open `terraform/modules/observability/main.tf`. Scroll to the dashboard
resource. *"Every service gets the same dashboard shape. On-call rotates
without retraining."*

### 3d — Observability (3 min)

Open the **Cloud Monitoring dashboard URL** from `terraform output`.

Walk the five tiles top-to-bottom:

1. Request count (req/s).
2. Active container instances.
3. Latency p50/p95/p99.
4. 5xx rate.
5. Application error log rate (driven by the log-based metric).

Then open **Logs Explorer** — show the saved query for the log-based metric.

> "All four observability outcomes from the management summary —
> *unified dashboards, logs, metrics, traces* — are in this module. Adding
> traces is the next sprint, OpenTelemetry on the application side."

### 3e — Rollback path (2 min — drop if behind)

Open `build-image.yml` in the browser, scroll to the **deploy** job. Walk
through how rollback works in the simple POC:

- The deploy job ran `terraform apply` with the new image and then smoke-tested
  it. If the smoke test fails, the run fails — but the new revision is live.
- Two rollback levers, both **without** any manual GitHub Actions trigger
  (there is no `workflow_dispatch` in CI by design):
  1. **Revert commit** — `git revert HEAD && git push`. Pre-commit runs,
     build-image rebuilds the previous code, deploy + smoke test redeploys it.
     Same path every code change takes — no special-case operator workflow.
  2. **Cloud Run console revision swap** — emergency lever when speed matters
     more than auditability. Pick a previous green revision and click
     "Rollback to this revision". Mean time to restore: ~30 seconds.
- The "no workflow_dispatch in CI" rule is a deliberate platform choice: it
  prevents the "I'll just dispatch a fix bypassing pre-commit" anti-pattern.

> "Auto-rollback and canary are deliberately out of scope for the walking
> stick. Once the platform is in production they're a focused workflow change
> we can ship in a sprint, without re-architecting anything."

## Segment 4 — Roadmap & success metrics (4 min)

Open the management summary on screen. Walk the **6-month roadmap** table:

- **Wks 1–6 Foundation** — what you just saw.
- **Wks 7–10 Self-service** — cost dashboards, observability rolled to all 17 services, ticket cap.
- **Wks 11–16 Launch-ready** — multi-tenant migration, GDPR data residency.

Then walk the **5 success metrics** tile:

> "Daily deploys (was 1/sprint). Lead time 1 day (was 5). 5% change failure
> rate. 40% cloud cost reduction from the multi-tenant work. < 2 hour
> new-service-time-to-first-deploy."

## Segment 5 — Wrap & ask (2 min)

> "What I need from you:
> 1. Endorsement for the Platform Operating Model — the bypass-declined rule
>    only works with leadership air cover.
> 2. The Cloud Engineering team rebadged as the Platform Team in the next
>    re-org cycle.
> 3. Permission to start Phase 01 next Monday."

Close with the management summary's headline:

> "By month 6, FinCore has a scalable, cost-efficient SaaS foundation where
> developers own their code from commit to production — and Cloud Engineering
> operates as a strategic enabler, not a bottleneck."

## If you have to drop something

Drop in this order: **3e** (rollback) → **3d** (observability deep-dive,
keep just the dashboard glance) → **2** (architecture, lean on the slide).
Never drop **3a–3c** — that's the proof.

## Failure modes during live demo

| If this breaks | Then do this |
|----------------|--------------|
| `git push` rejected | Walk through the failed-deploy rollback story on `terraform.yml` instead of running it live |
| Cloud Build fails | Skip to the dashboard; explain the change went through earlier, point at the run history |
| Smoke test fails on the new revision | Narrate the rollback live — open the **Run workflow** dialog on Terraform, set `action=apply` + previous `image_ref`, kick it off. Use this as segment 3e. |
| Beamer dies | Hand out printed management summary; talk through the architecture diagram on a whiteboard |

## Checklist 30 minutes before the meeting

- [ ] `gh run list -R pp-fcy/BUX-task --limit 5` — pipeline is green
- [ ] `terraform output -raw load_balancer_ip` — service is up; `curl https://<ip>/` returns `Hello World`
- [ ] `terraform output -raw dashboard_url` opens the dashboard
- [ ] `git status` is clean
- [ ] Demo branch `demo/change-text` exists and has one trivial diff
- [ ] Battery > 50%, charger plugged in
