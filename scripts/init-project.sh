#!/usr/bin/env bash
##############################################################################
# init-project.sh – One-shot project bootstrap
#
# Run once (idempotent) to set up everything needed before the first
# GitHub Actions run:
#
#   Phase 1 – GCS bucket for Terraform remote state
#   Phase 2 – Workload Identity Federation (OIDC → GCP, no long-lived keys)
#   Phase 3 – IAM roles for the CI/CD service account
#   Phase 4 – Push WIF secrets to GitHub Actions
#
# Prerequisites:
#   • gcloud  authenticated as a project Owner (or equivalent)
#   • gh      authenticated (gh auth login) — needed for Phase 4 only
#
# Defaults match this repository; override with env vars before running:
#   GCP_PROJECT_ID      default: bux-project-490819
#   GITHUB_REPO         default: pp-fcy/BUX-task
#   TF_STATE_BUCKET     default: cfan-bux-tfstate
#   TF_STATE_REGION     default: europe-west1
#   WIF_POOL_ID         default: github-actions-pool
#   WIF_PROVIDER_ID     default: github-provider
#   GITHUB_ACTIONS_SA_ID default: github-actions-sa
#
# Usage:
#   ./scripts/init-project.sh           # use all defaults
#   GCP_PROJECT_ID=my-project \
#   GITHUB_REPO=org/repo \
#   ./scripts/init-project.sh
#
# Individual helper scripts (still available):
#   scripts/terraform-init-env.sh        – local terraform init for prod/dev
#   scripts/check-github-actions-environment.sh – verify secrets/env setup
##############################################################################
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
skip()    { echo -e "${YELLOW}  ·${RESET} $* (already exists, skipping)"; }
die()     { echo -e "${RED}${SCRIPT_NAME}: error:${RESET} $*" >&2; exit 1; }

usage() {
  sed -n '1,35p' "$0" | tail -n +2
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# ── Configuration ────────────────────────────────────────────────────────────
GCP_PROJECT_ID="${GCP_PROJECT_ID:-bux-project-490819}"
GITHUB_REPO="${GITHUB_REPO:-pp-fcy/BUX-task}"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-cfan-bux-tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-europe-west1}"

WIF_POOL_ID="${WIF_POOL_ID:-github-actions-pool}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github-provider}"
GITHUB_ACTIONS_SA_ID="${GITHUB_ACTIONS_SA_ID:-github-actions-sa}"
SA_EMAIL="${GITHUB_ACTIONS_SA_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# ── Validate inputs ──────────────────────────────────────────────────────────
[[ "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || die "GITHUB_REPO must be org/repo (got: ${GITHUB_REPO})"

echo ""
echo -e "${BOLD}Project bootstrap${RESET}"
echo "  GCP project   : ${GCP_PROJECT_ID}"
echo "  GitHub repo   : ${GITHUB_REPO}"
echo "  TF state      : gs://${TF_STATE_BUCKET}  (region: ${TF_STATE_REGION})"
echo "  WIF pool      : ${WIF_POOL_ID} / ${WIF_PROVIDER_ID}"
echo "  CI/CD SA      : ${SA_EMAIL}"
echo ""

# ── Prerequisites ────────────────────────────────────────────────────────────
info "Checking prerequisites..."

command -v gcloud &>/dev/null || die "gcloud not found — install the Google Cloud SDK"
gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "gcloud not authenticated — run: gcloud auth login"

SKIP_GH=false
if ! command -v gh &>/dev/null; then
  echo -e "${YELLOW}  ⚠${RESET}  gh CLI not found — Phase 4 (push GitHub secrets) will be skipped."
  echo "     Install: https://cli.github.com/  then run: gh auth login"
  SKIP_GH=true
elif ! gh auth status &>/dev/null; then
  echo -e "${YELLOW}  ⚠${RESET}  gh not authenticated — Phase 4 will be skipped. Run: gh auth login"
  SKIP_GH=true
fi

success "Prerequisites OK"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 1 – GCS bucket for Terraform remote state
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 1 – Terraform state bucket${RESET}"

info "Enabling storage API..."
gcloud services enable storage.googleapis.com --project="${GCP_PROJECT_ID}" --quiet

BUCKET_URI="gs://${TF_STATE_BUCKET}"

if gcloud storage buckets describe "${BUCKET_URI}" --project="${GCP_PROJECT_ID}" &>/dev/null; then
  skip "Bucket ${BUCKET_URI}"
else
  info "Creating bucket ${BUCKET_URI} in ${TF_STATE_REGION}..."
  gcloud storage buckets create "${BUCKET_URI}" \
    --project="${GCP_PROJECT_ID}" \
    --location="${TF_STATE_REGION}" \
    --uniform-bucket-level-access \
    --quiet
  success "Bucket created"
fi

info "Ensuring versioning is enabled (protects state history)..."
gcloud storage buckets update "${BUCKET_URI}" --versioning --quiet
success "Versioning enabled"

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 2 – Workload Identity Federation
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 2 – Workload Identity Federation${RESET}"

info "Enabling required APIs..."
gcloud services enable \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  --project="${GCP_PROJECT_ID}" --quiet
success "APIs enabled"

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')"
[[ -n "${PROJECT_NUMBER}" ]] || die "could not resolve project number for ${GCP_PROJECT_ID}"

# WIF pool
info "Workload Identity Pool: ${WIF_POOL_ID}"
if gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
  --project="${GCP_PROJECT_ID}" --location=global &>/dev/null; then
  skip "${WIF_POOL_ID}"
else
  gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --location=global \
    --display-name="GitHub Actions Pool" \
    --description="Keyless auth pool for GitHub Actions CI/CD"
  success "Pool created"
fi

# OIDC provider
info "OIDC provider: ${WIF_PROVIDER_ID}"
ATTR_MAP="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref"
ATTR_COND="assertion.repository=='${GITHUB_REPO}'"

if gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --project="${GCP_PROJECT_ID}" --location=global \
  --workload-identity-pool="${WIF_POOL_ID}" &>/dev/null; then
  skip "${WIF_PROVIDER_ID}"
else
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --location=global \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --display-name="GitHub OIDC Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="${ATTR_MAP}" \
    --attribute-condition="${ATTR_COND}"
  success "Provider created"
fi

# CI/CD service account
info "Service account: ${SA_EMAIL}"
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT_ID}" &>/dev/null; then
  skip "${SA_EMAIL}"
else
  gcloud iam service-accounts create "${GITHUB_ACTIONS_SA_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions CI/CD" \
    --description="Used by GitHub Actions via WIF (no long-lived keys)"
  success "Service account created"
fi

# Bind WIF principal → SA
POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
PRINCIPAL_SET="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${GITHUB_REPO}"

info "Binding WIF principal to service account..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${PRINCIPAL_SET}" \
  --quiet
success "WIF binding set"

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 3 – IAM roles for the CI/CD service account
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 3 – IAM role bindings${RESET}"

ROLES=(
  # Cloud Run: deploy services, act as the Cloud Run runtime SA
  roles/run.admin
  roles/iam.serviceAccountUser
  roles/iam.serviceAccountTokenCreator

  # Terraform remote state (GCS)
  roles/storage.admin

  # Networking / Load Balancer / Cloud Armor
  roles/compute.admin
  roles/compute.securityAdmin

  # Artifact Registry (Terraform creates the repo; build jobs push images)
  roles/artifactregistry.admin

  # Enable / manage GCP APIs via google_project_service in Terraform
  roles/serviceusage.serviceUsageAdmin

  # Cloud Build: submit image builds
  roles/cloudbuild.builds.editor

  # Cloud Logging: create/update log-based metrics (used by observability module)
  roles/logging.configWriter

  # Cloud Monitoring: create/update dashboards (used by observability module)
  roles/monitoring.editor

  # List project resources (needed in some org / VPC-SC setups)
  roles/browser
)

info "Binding ${#ROLES[@]} roles to ${SA_EMAIL}..."
for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --quiet
  success "${role}"
done

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 4 – Push WIF secrets to GitHub Actions
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 4 – GitHub Actions secrets${RESET}"

PROVIDER_NAME="$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --project="${GCP_PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --format='value(name)')"

if [[ "$SKIP_GH" == "true" ]]; then
  echo -e "${YELLOW}  Skipped — set these manually:${RESET}"
  echo ""
  echo "  Settings → Secrets and variables → Actions → Repository secrets:"
  echo "    WORKLOAD_IDENTITY_PROVIDER  =  ${PROVIDER_NAME}"
  echo "    GCP_SERVICE_ACCOUNT         =  ${SA_EMAIL}"
else
  info "Setting repository secrets on ${GITHUB_REPO}..."
  echo "${PROVIDER_NAME}" | gh secret set WORKLOAD_IDENTITY_PROVIDER -R "${GITHUB_REPO}"
  echo "${SA_EMAIL}"       | gh secret set GCP_SERVICE_ACCOUNT        -R "${GITHUB_REPO}"
  success "WORKLOAD_IDENTITY_PROVIDER set"
  success "GCP_SERVICE_ACCOUNT set"

  # Also push to the 'production' environment if it exists
  if gh api "repos/${GITHUB_REPO}/environments/production" &>/dev/null 2>&1; then
    info "Also setting secrets on 'production' environment..."
    echo "${PROVIDER_NAME}" | gh secret set WORKLOAD_IDENTITY_PROVIDER -R "${GITHUB_REPO}" -e production
    echo "${SA_EMAIL}"       | gh secret set GCP_SERVICE_ACCOUNT        -R "${GITHUB_REPO}" -e production
    success "production environment secrets set"
  else
    echo -e "${YELLOW}  ·${RESET}  'production' environment not found on GitHub — skipping environment secrets."
    echo "     Create it at: Settings → Environments → New environment → name: production"
    echo "     Then re-run this script (idempotent) or set the same two secrets there manually."
  fi
fi

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Bootstrap complete ✓${RESET}"
echo ""
echo "  GCS state bucket : ${BUCKET_URI}  (${TF_STATE_REGION})"
echo "  WIF provider     : ${PROVIDER_NAME}"
echo "  CI/CD SA         : ${SA_EMAIL}"
echo ""
echo "Next steps:"
echo "  1. Verify terraform/env/prod.backend.hcl matches:"
echo "       bucket = \"${TF_STATE_BUCKET}\""
echo "       prefix = \"what-time-is-it/state\""
echo ""
echo "  2. Run local Terraform init (first time):"
echo "       ./scripts/terraform-init-env.sh prod"
echo ""
echo "  3. Verify GitHub Actions environment & secrets:"
echo "       ./scripts/check-github-actions-environment.sh"
echo ""
echo "  4. Push a commit that changes terraform/ to trigger the first"
echo "     'Terraform Apply (infra)' run via GitHub Actions."
echo ""
