# AI Prompts — Train of Thought

This file documents the prompts used with Claude (Anthropic) to design and build this solution.
Model: Claude Sonnet via Claude desktop app (Cowork mode).

---

## 1. Architecture design

**Prompt:**
> Design a GCP infrastructure for a simple Kotlin/Ktor web application with the following requirements:
> - Cloud Run as the compute layer, reachable from the internet but protected by Cloud Armor
> - High availability across multiple regions behind a Global Load Balancer
> - Terraform as the IaC tool
> - GitHub Actions for CI/CD
> - Blue/green deployment where the secondary region is tested before the primary is updated
> - Workload Identity Federation for keyless GitHub Actions → GCP auth (no long-lived keys)
>
> Propose the resource structure and Terraform module layout.

**What Claude produced:** A module-based Terraform layout with two Cloud Run v2 services (europe-west1 primary, europe-west4 secondary), a Global HTTP(S) Load Balancer with two NEGs, a Cloud Armor security policy, and an Artifact Registry. WIF with a GitHub OIDC provider for keyless auth.

---

## 2. Terraform — Cloud Run + Load Balancer + Cloud Armor

**Prompt:**
> Write Terraform code for the following GCP resources:
> - Two Cloud Run v2 services in europe-west1 (primary) and europe-west4 (secondary)
> - Ingress restricted to internal-and-cloud-load-balancing (no direct public access)
> - Global HTTP(S) Load Balancer with a serverless NEG for each Cloud Run service
> - Cloud Armor security policy with rate limiting and common OWASP rules attached to the backend service
> - Artifact Registry repository for Docker images
> - All APIs enabled via google_project_service
>
> Use a reusable module under terraform/modules/what-time-is-it. Accept container_image as a variable so the image can be updated without recreating infrastructure.

---

## 3. Terraform — remote state and environment config

**Prompt:**
> Set up Terraform remote state using a GCS backend. Separate backend config from variable values so the same module can target prod and dev environments. Use:
> - terraform/env/prod.backend.hcl for the GCS bucket and prefix
> - terraform/env/prod.tfvars for project_id, regions, app_name, scaling config
>
> Also write a helper script scripts/terraform-init-env.sh that initialises the backend for prod or dev.

---

## 4. Docker image — build the upstream app

**Prompt:**
> The upstream app at https://github.com/buxapp/what-time-is-it uses Kotlin 1.4.20 with Maven.
> Write a multi-stage Dockerfile that:
> - Builds the fat JAR using Maven
> - Produces a minimal runtime image
> - Works on linux/amd64 (Cloud Run target platform)
>
> The Dockerfile lives in what-time-is-it/ inside this repo so we can control the build without forking the app.

**Note:** Initial attempt used JDK 17 which is incompatible with Kotlin 1.4.20. Claude identified the incompatibility and downgraded both build and runtime stages to eclipse-temurin:11-jdk-alpine, and updated pom.xml compiler target to 11.

---

## 5. CI/CD pipeline design

**Prompt:**
> Design a GitHub Actions CI/CD pipeline for this repo with the following workflows:
>
> - pre-commit.yml: runs pre-commit hooks on pull_request and push to main
> - terraform.yml: runs terraform plan after pre-commit passes on a PR (posts result as PR comment); runs terraform apply after pre-commit passes on a push to main, but only if terraform/ files changed
> - build-image.yml: builds and pushes a Docker image via Cloud Build when what-time-is-it/ files change on push to main (also after pre-commit passes); triggers the release workflow after a successful build
> - release.yml: orchestrates blue/green deploy by calling terraform.yml as a reusable workflow
>
> All workflows that touch production must use Workload Identity Federation for GCP auth.
> Use a shared concurrency group terraform-production to prevent parallel Terraform runs.

---

## 6. Blue/green deployment workflow

**Prompt:**
> Implement blue/green deployment in terraform.yml as a reusable workflow (workflow_call) called by release.yml:
>
> Phase 1 — deploy to secondary (europe-west4) only using terraform apply -target on the secondary Cloud Run service. Before running the smoke test, temporarily open Cloud Run ingress to "all" so the test can hit the Cloud Run URL directly (bypassing the Load Balancer, which would route to both regions). After the test, always restore ingress to internal-and-cloud-load-balancing.
>
> Smoke test: verify GET /amsterdam returns HTTP 200 with "in Amsterdam" and a timestamp; verify GET /london returns HTTP 200 with "in London" and a timestamp.
>
> Phase 2 — only if phase 1 passes: deploy to primary (europe-west1) with a full terraform apply to reconcile all resources.
>
> Also implement a rollback path: if rollback_image input is provided, skip the normal deploy and apply that image to both regions immediately.
>
> Auto-rollback secondary if the smoke test fails.

---

## 7. Workload Identity Federation — bootstrap and IAM

**Prompt:**
> Write a single idempotent bash script scripts/init-project.sh that bootstraps everything needed before the first GitHub Actions run:
>
> Phase 1: Create a GCS bucket for Terraform state with versioning and uniform bucket-level access enabled.
> Phase 2: Create a WIF pool, OIDC provider (issuer: token.actions.githubusercontent.com), and a github-actions-sa service account. Bind the WIF principalSet for the GitHub repo to the SA with workloadIdentityUser.
> Phase 3: Grant the SA all IAM roles it needs: run.admin, iam.serviceAccountUser, iam.serviceAccountTokenCreator, storage.admin, compute.admin, compute.securityAdmin, artifactregistry.admin, serviceusage.serviceUsageAdmin, cloudbuild.builds.editor, browser.
> Phase 4: Push WORKLOAD_IDENTITY_PROVIDER and GCP_SERVICE_ACCOUNT as GitHub Actions secrets to both the repository and the production environment using the gh CLI.
>
> Each step should check if the resource already exists before creating it. Print a clear summary at the end.

---

## 8. Pre-commit and code quality

**Prompt:**
> Set up a pre-commit configuration for this repo covering:
> - Terraform formatting and validation (terraform fmt, terraform validate)
> - Standard file hygiene (trailing whitespace, end-of-file newline, YAML/JSON syntax)
> - Shell script linting with shellcheck
>
> Write a pre-commit.yml GitHub Actions workflow that runs the hooks on both pull_request and push to main so downstream workflows (terraform plan, terraform apply, build-image) can use workflow_run to gate on its result.

---

## 9. Workflow reliability fixes

Several GitHub Actions edge cases required targeted fixes, each prompted as a specific problem:

**Concurrency deadlock between release.yml and terraform.yml:**
> release.yml holds the terraform-production concurrency lock and calls terraform.yml as a reusable workflow. terraform.yml also tries to acquire terraform-production, causing a deadlock. Fix it so the reusable workflow never conflicts with its caller.

**event_name value inside a reusable workflow:**
> Inside a reusable workflow triggered via workflow_call, what does github.event_name return? The deploy jobs are conditioned on github.event_name == 'workflow_call' but they are always skipped.

**Inputs passing null through workflow_call with: blocks:**
> inputs.image_ref is set by the caller but arrives as null inside terraform.yml when passed via with: image_ref: ${{ inputs.image_ref }}. The jobs run but IMAGE_REF is empty so Terraform deploys the hello-world fallback. Fix the value passing.

---

## 10. IDP walking-stick reframe (Xebia Platform Architect Assessment)

The repo originally targeted the BUX DevOps assignment (single Kotlin/Ktor service on
Cloud Run). The Xebia Platform Architect Assessment asked for a "walking stick" demo
of an Internal Developer Platform plus a management summary and 30-min presentation.
Rather than start from scratch, I reframed this repo as the IDP walking stick — the
underlying Cloud Run + Terraform + GitHub Actions + WIF stack already covered three
of the four required components.

**Prompt (scope decision):**
> The existing repo runs one Cloud Run service. The Xebia management summary describes
> a future-state IDP on shared GKE + Istio + ArgoCD. Given the assessment explicitly
> says "don't over-engineer the walking stick", what's the right scope for the rewrite?
> Should I pivot to GKE, restructure into idp/ + services/, or keep Cloud Run and
> reframe + add observability?

**Decision:** Keep Cloud Run, reframe as IDP, add the missing observability layer.
The Terraform module boundary becomes the seam — replacing the contents of
`modules/what-time-is-it/` with Helm + ArgoCD later is a drop-in change.

**Prompt (observability module):**
> Write a reusable Terraform module under terraform/modules/observability/ that gives
> every IDP service the same baseline observability:
> - Cloud Monitoring dashboard with req/s, instance count, p50/p95/p99 latency, 5xx rate, error log rate
> - Log-based metric counting Cloud Run severity>=ERROR entries
> - Uptime check against the Load Balancer (optional via empty host)
> - Alert policies for high error rate and uptime failure, optionally wired to email channels
>
> Output a `dashboard_url` so the root composition can surface the deep-link via
> `terraform output` for the live demo.

**Prompt (docs):**
> Generate four docs that an audience of VP Eng + Senior Cloud Engineer can read
> in any order:
> 1. PLATFORM_OPERATING_MODEL.md — Team Topologies, RACI, golden-path principle
> 2. IDP_ARCHITECTURE.md — 5-layer IDP map, runtime diagram, trade-offs
> 3. SERVICE_TEMPLATE.md — 9-step golden path, < 2 hours to first deploy
> 4. DEMO_SCRIPT.md — minute-by-minute 30-min walkthrough
>
> Tone: confident but honest about cuts. Cite the management summary numbers
> (40% cost reduction, daily deploys, < 2hr time-to-first-deploy) so the docs
> reinforce rather than contradict the one-pager.

**Prompt (README rewrite):**
> Rewrite the top-level README so:
> - The first thing a VP of Engineering sees is the Management Summary section
> - The 4 walking-stick components from the assignment are mapped to repo paths
> - Three reading orders for three audiences (VP, Sr Cloud Eng, product dev) are spelled out
> - "What we cut and when we add it back" is honest, not buried
> - All existing bootstrap / WIF / Terraform / GitHub Actions content is preserved

---

## 11. Sample-service simplification + portal removal

The Kotlin/Ktor `what-time-is-it` service (Maven build, Helm chart, two
endpoints, ~30 files) was distracting from the platform's value during the
30-minute demo. Same call applied to the catalog-info.yaml and Backstage
references: a portal is a post-launch concern, and pretending we have one in
the walking stick muddies the message.

**Prompt (sample service swap):**
> Replace the Kotlin/Ktor service in what-time-is-it/ with a minimal HTTP
> server that returns "Hello World" on / and "ok" on /healthz. Stdlib only,
> no dependencies, single-stage Alpine image, runs as non-root, listens on
> $PORT (default 8080), graceful SIGTERM handling. Delete pom.xml, mvnw, .mvn,
> src/, test/, resources/, chart/. Update the smoke test in terraform.yml from
> /amsterdam + /london to / + /healthz, and the observability module's
> uptime_check_path default from /amsterdam to /.

**Prompt (Backstage removal):**
> Strip every Backstage / catalog-info.yaml reference from the repo. Delete
> catalog-info.yaml. In the docs, reframe the golden path as "just GitHub
> CI/CD" — repo template + reusable workflows. A portal (Backstage or
> similar) becomes a post-launch item in the cuts table. Touch:
> README.md, docs/IDP_ARCHITECTURE.md, docs/SERVICE_TEMPLATE.md,
> docs/DEMO_SCRIPT.md, PROMPTS.md.

---

## 12. Drop the canary, make it a simple POC

The blue/green deploy with secondary region + auto-rollback was overkill for a
30-min walking-stick demo and was distracting from the platform shape. The
walking stick now deploys to a single Cloud Run service in one region; smoke
test on the new revision is the safety net; rollback is a manual re-run of the
deploy job with a previous image tag.

**Prompt (canary removal):**
> Remove the canary / blue-green deployment from this repo and reframe it as a
> simple POC for the IDP demo:
> - Drop the `secondary` Cloud Run service, secondary IAM, secondary NEG; LB
>   has one backend.
> - Drop the `secondary_region` variable from the module, root, and tfvars.
> - Replace the `deploy-secondary` + `deploy-primary` + `rollback` jobs in
>   `terraform.yml` with a single `deploy` job: terraform apply with the new
>   image, then smoke test `/` and `/healthz`.
> - Delete `release.yml`. Have `build-image.yml` call `terraform.yml`'s deploy
>   job directly via `workflow_call`.
> - Update README, IDP_ARCHITECTURE, SERVICE_TEMPLATE, PLATFORM_OPERATING_MODEL,
>   and DEMO_SCRIPT to drop blue/green / dual-region / auto-rollback narrative.
>   Add HA + canary as items in the "what we cut and when we add it back" table.

---

## 13. Fix GitHub Actions "Startup failure" — drop the workflow_call indirection

After the canary removal, push to main triggered Pre-commit → terraform.yml via
workflow_run, which reported **Startup failure** (run never started). Root
cause: terraform.yml had three triggers in the same file — `workflow_run`,
`workflow_dispatch`, and `workflow_call` — and a deploy job whose `if:`
referenced `inputs.image_ref`. When the file is loaded for a `workflow_run`
event, the `inputs` context is null; references to `inputs.X` in job-level
`if:` conditions tip GitHub Actions into a startup failure on workflows that
mix triggers like this.

**Prompt (workflow restructure):**
> Drop the workflow_call trigger from terraform.yml entirely. Move the deploy
> logic (terraform apply with the new image_ref + smoke test) inline into
> build-image.yml as its own job. Keep both workflows in the same
> `terraform-production` concurrency group so they serialise. Update README,
> SERVICE_TEMPLATE, and DEMO_SCRIPT to drop references to "the deploy job in
> terraform.yml" / "calls terraform.yml as a reusable workflow".

The result is two simple, single-trigger-shape workflows: terraform.yml does
plan + infra apply; build-image.yml does build + image deploy. No reusable
workflow indirection, no dual-trigger `inputs` quirks.

---

## 14. Remove all manual triggers — single supported path

The platform's "one supported way to ship a service" rule was being undercut
by `workflow_dispatch` escape hatches in CI. Every dispatch button is a
temptation to bypass the pre-commit gate during an incident; that's exactly
the anti-pattern the operating model rules out.

**Prompt (drop manual triggers):**
> Remove `workflow_dispatch` from every workflow. Specifically:
> - terraform.yml: drop the dispatch trigger and the `inputs.action` references
>   in the plan / check-tf-changes if conditions. Workflow_run is the only
>   trigger; plan runs on PR, apply runs on push to main.
> - build-image.yml: drop the dispatch trigger and the `inputs.trigger_deploy`
>   gate on the deploy job. workflow_run + repository_dispatch only.
> - destroy.yml: delete the file (purely manual; orphaned without
>   workflow_dispatch). `terraform destroy` is still available locally.
> Update README, IDP_ARCHITECTURE, SERVICE_TEMPLATE, and DEMO_SCRIPT to
> describe rollback as either a revert commit (which re-runs the pipeline)
> or a Cloud Run console revision swap as the emergency lever.

The trade-off is honest: you lose a one-click rollback button in favour of a
single, audited code path. Rollback is slower (revert commit + pipeline run)
but no faster than the original deploy was, which is fine for a SaaS on the
launch ramp. The Cloud Run console revision swap stays as a last-resort lever.

---

## Tools used

- **AI:** Claude Sonnet (Anthropic) via Claude desktop app (Cowork mode)
- **Usage pattern:** Requirements-first prompts for each component, followed by targeted fix prompts for runtime issues discovered during testing. For the IDP reframe (section 10), one scope-decision prompt followed by separate prompts per artifact.
- **Human decisions:** GCP project and region selection, naming conventions, cost/complexity trade-offs (single LB vs per-region, Cloud Armor rule set scope, GCP-native observability vs Prometheus/Grafana, GitHub repo template vs Cookiecutter vs running a portal).
