# Platform Operating Model

> Companion to the [Management Summary](../README.md#management-summary). One pager
> for the leadership team; this doc is the engineering-side detail behind it.

## Why we are changing the model

Today **Cloud Engineering is a gatekeeper**. Every infra change for the 17 product
teams flows through them. The result, in their own words:

| Symptom | Quote |
|---------|-------|
| Bottleneck | *"Developers are not taking responsibility and rely on us for every infra change."* — Cloud Engineer |
| Powerlessness | *"We can only build code; infra and deployments go through Cloud Engineering."* — Developer |
| Burnout | *"A bunch of developers are working overtime."* — Engineering Manager |
| No automation budget | *"We don't have time to automate tests because of manual sprint pressure."* — QA Lead |

The fix is structural, not motivational: **change who owns what** so the bottleneck
stops being a person.

## Team Topologies (the new shape)

We re-cast the existing teams into four well-known interaction modes:

| Team | Topology | Headcount today | Mandate |
|------|----------|-----------------|---------|
| **Platform Team** | Platform | 1 (was Cloud Eng) | Owns the IDP. Builds & maintains golden paths. Treats developers as customers. |
| **17 Product Teams** | Stream-aligned | 17 | Own service code, infra (via golden paths), on-call, SLOs. |
| **QA** | Enabling (transient) | 1 | Coaches teams to own their own automated tests. Dissolves into product teams once test automation is established. |
| **Security** | Enabling | 1 | Defines policy-as-code (OPA/Checkov), reviews exceptions. Does **not** sit in every PR. |

The phrase "1 Platform team for 17 stream-aligned teams" is the headline. It
matches Team Topologies' guidance on platform team sizing for an organisation of
this scale.

## What "self-service" actually means

Self-service is **not** "developers can do anything". It is "the 80% of common
changes happen with zero ticket".

| Change | Old path | New path |
|--------|---------|---------|
| Deploy a code change | Cloud Eng promotes to prod after sprint | `git push` → CI → terraform apply with the new image → smoke test (this repo demonstrates this) |
| Add a Cloud Run service | Ticket to Cloud Eng (~3 days) | Copy `terraform/modules/what-time-is-it/`, change name, open PR. Plan posted as PR comment, apply on merge. |
| Add a dashboard | Hand-rolled in console by Cloud Eng | Module `observability` instantiated in the service composition. |
| Add an alert | Hand-rolled in console | `alert_notification_emails = [...]` in tfvars. |
| Provision a new GCP API | Ticket to Cloud Eng | Add to `google_project_service.apis` for-each set. |
| Bypass Cloud Armor for a partner | **Still goes through Security** | Exception process, OPA policy gate. |

## RACI on the critical paths

| Activity | Product Team | Platform Team | Security | QA (transient) |
|----------|:---:|:---:|:---:|:---:|
| Write service code | **R/A** | C | I | C |
| Run unit & integration tests | **R/A** | C | I | C |
| Deploy to prod | **R/A** | I | I | I |
| On-call for the service | **R/A** | C (escalate) | I | – |
| Pick the cloud, region, or HA topology | I | **R/A** | C | – |
| Set baseline security policy (Cloud Armor, WIF) | I | C | **R/A** | – |
| Approve compliance exceptions (GDPR data residency) | I | C | **R/A** | – |
| Maintain Terraform module registry | C | **R/A** | C | – |
| Write the **first** test for a new service | **R/A** | I | I | C (coach) |
| Run the on-call rotation tooling | I | **R/A** | I | – |

R = Responsible, A = Accountable, C = Consulted, I = Informed.

## Golden path principle

> **There is one supported way to ship a service. If you take it, the platform
> team owns the failure modes. If you go around it, you own them.**

This is the "Bypass requests are declined" line in the management summary. It is
deliberate: with 17 product teams and a 6-month deadline, we cannot
support N variations of "nearly the same thing". Exceptions go through the
Architecture Review Board (existing process, kept for governance reasons).

## What the Platform Team does NOT do

To prevent the gatekeeper pattern from re-emerging:

- **Does not deploy** product code on behalf of teams.
- **Does not write** product-team Terraform service definitions (it provides the
  module; teams instantiate it).
- **Does not approve** every PR — only the platform repo PRs.
- **Does not own** product team SLOs or burn rates.

## How we measure the model

Two sets of metrics, both rolled up monthly to the VP of Engineering:

**DORA (developer experience)**
- Deployment frequency: target daily per service (was 1× per sprint).
- Lead time for change: target ≤ 1 day (was ≈ 5 days).
- Change failure rate: target ≤ 5% (currently unmeasured).
- Mean time to restore: target ≤ 1 hour (currently undefined).

**Platform health (platform team OKRs)**
- New-service-time-to-first-deploy: target ≤ 2 hours.
- Infra tickets handled by platform team per week: target ≤ 5.
- Golden-path adoption rate: target 100% of new services, ≥ 90% of existing
  services migrated by launch.

These are the same numbers in the Management Summary's "Projected Success
Metrics" tile.

## Migration plan (16 weeks, mirrors the management summary roadmap)

| Phase | Weeks | What changes for product teams |
|-------|-------|-------------------------------|
| **01 — Foundation** | 1–6 | Golden-path service template ready. New services use it. Existing services unchanged. |
| **02 — Self-service** | 7–10 | Cost dashboards + observability rolled out. Cloud Eng tickets capped at ≤ 5/wk; bypass requests routed to ARB. |
| **03 — Launch-ready** | 11–16 | Multi-tenant migration + GDPR enforcement. Per-tenant clusters decommissioned. |

The "walking stick" demo in this repo is the proof that Phase 01 is achievable
in the timeline.
