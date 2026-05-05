#!/usr/bin/env bash
##############################################################################
# migrate-repo.sh – Migrate this repo to a new GitHub remote
#
# Run once after pushing the code to a new GitHub repository. This script
# re-wires Workload Identity Federation and GitHub Actions secrets so that
# CI/CD works from the new repo without touching the GCP project or state.
#
# What it does:
#   Phase 1 – Push code to the new GitHub remote
#   Phase 2 – Update WIF provider attribute condition (old repo → new repo)
#   Phase 3 – Update WIF IAM principal binding   (old repo → new repo)
#   Phase 4 – Push Actions secrets to the new repo
#
# Prerequisites:
#   • git   with the local repo checked out
#   • gcloud authenticated as project Owner
#   • gh    authenticated (gh auth login)
#
# Defaults (override with env vars):
#   OLD_GITHUB_REPO   default: pp-fcy/BUX-test
#   NEW_GITHUB_REPO   default: pp-fcy/Xebia-terraform
#   NEW_GIT_REMOTE    default: git@github.com:pp-fcy/Xebia-terraform.git
#   GCP_PROJECT_ID    default: bux-project-490819
#   WIF_POOL_ID       default: github-actions-pool
#   WIF_PROVIDER_ID   default: github-provider
#   GITHUB_ACTIONS_SA_ID  default: github-actions-sa
#
# Usage:
#   ./scripts/migrate-repo.sh
#   NEW_GITHUB_REPO=other-org/other-repo ./scripts/migrate-repo.sh
##############################################################################
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${RESET}  $*"; }
die()     { echo -e "${RED}${SCRIPT_NAME}: error:${RESET} $*" >&2; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '1,30p' "$0" | tail -n +2; exit 0; }

# ── Configuration ─────────────────────────────────────────────────────────────
OLD_GITHUB_REPO="${OLD_GITHUB_REPO:-pp-fcy/BUX-test}"
NEW_GITHUB_REPO="${NEW_GITHUB_REPO:-pp-fcy/Xebia-terraform}"
NEW_GIT_REMOTE="${NEW_GIT_REMOTE:-git@github.com:pp-fcy/Xebia-terraform.git}"

GCP_PROJECT_ID="${GCP_PROJECT_ID:-bux-project-490819}"
WIF_POOL_ID="${WIF_POOL_ID:-github-actions-pool}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github-provider}"
GITHUB_ACTIONS_SA_ID="${GITHUB_ACTIONS_SA_ID:-github-actions-sa}"
SA_EMAIL="${GITHUB_ACTIONS_SA_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo -e "${BOLD}Repo migration${RESET}"
echo "  From          : ${OLD_GITHUB_REPO}"
echo "  To            : ${NEW_GITHUB_REPO}  (${NEW_GIT_REMOTE})"
echo "  GCP project   : ${GCP_PROJECT_ID}"
echo "  CI/CD SA      : ${SA_EMAIL}"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
info "Checking prerequisites..."
command -v git    &>/dev/null || die "git not found"
command -v gcloud &>/dev/null || die "gcloud not found — install the Google Cloud SDK"
command -v gh     &>/dev/null || die "gh CLI not found — install from https://cli.github.com/"
gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "gcloud not authenticated — run: gcloud auth login"
gh auth status &>/dev/null \
  || die "gh not authenticated — run: gh auth login"
success "Prerequisites OK"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 1 – Push code to the new GitHub remote
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 1 – Push code to new remote${RESET}"

CURRENT_REMOTE="$(git remote get-url origin 2>/dev/null || echo '')"

if [[ "${CURRENT_REMOTE}" == "${NEW_GIT_REMOTE}" ]]; then
  info "origin already points to ${NEW_GIT_REMOTE}, skipping remote update."
else
  info "Adding 'new-origin' remote → ${NEW_GIT_REMOTE}"
  git remote remove new-origin 2>/dev/null || true
  git remote add new-origin "${NEW_GIT_REMOTE}"

  info "Pushing all branches and tags to new remote..."
  git push new-origin --all
  git push new-origin --tags

  info "Updating origin → ${NEW_GIT_REMOTE}"
  git remote set-url origin "${NEW_GIT_REMOTE}"
  git remote remove new-origin

  success "Code pushed and origin updated to ${NEW_GIT_REMOTE}"
fi

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 2 – Update WIF provider attribute condition
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 2 – Update WIF provider attribute condition${RESET}"

info "Updating attribute condition: ${OLD_GITHUB_REPO} → ${NEW_GITHUB_REPO}"
gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER_ID}" \
  --project="${GCP_PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --attribute-condition="assertion.repository=='${NEW_GITHUB_REPO}'" \
  --quiet
success "Provider attribute condition updated"

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 3 – Update WIF IAM principal binding
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 3 – Update WIF IAM binding${RESET}"

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')"
[[ -n "${PROJECT_NUMBER}" ]] || die "could not resolve project number for ${GCP_PROJECT_ID}"

POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
OLD_PRINCIPAL="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${OLD_GITHUB_REPO}"
NEW_PRINCIPAL="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${NEW_GITHUB_REPO}"

info "Removing old principal binding for ${OLD_GITHUB_REPO}..."
if gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" \
    --project="${GCP_PROJECT_ID}" --format=json 2>/dev/null \
    | grep -q "${OLD_GITHUB_REPO}"; then
  gcloud iam service-accounts remove-iam-policy-binding "${SA_EMAIL}" \
    --project="${GCP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${OLD_PRINCIPAL}" \
    --quiet
  success "Old binding removed"
else
  warn "Old binding for ${OLD_GITHUB_REPO} not found — already removed or never existed."
fi

info "Adding new principal binding for ${NEW_GITHUB_REPO}..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${NEW_PRINCIPAL}" \
  --quiet
success "New WIF binding set for ${NEW_GITHUB_REPO}"

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 4 – Push Actions secrets to the new repo
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Phase 4 – GitHub Actions secrets${RESET}"

PROVIDER_NAME="$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --project="${GCP_PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --format='value(name)')"

info "Setting repository secrets on ${NEW_GITHUB_REPO}..."
echo "${PROVIDER_NAME}" | gh secret set WORKLOAD_IDENTITY_PROVIDER -R "${NEW_GITHUB_REPO}"
echo "${SA_EMAIL}"       | gh secret set GCP_SERVICE_ACCOUNT        -R "${NEW_GITHUB_REPO}"
success "WORKLOAD_IDENTITY_PROVIDER set"
success "GCP_SERVICE_ACCOUNT set"

# Also set on the 'production' environment if it exists
if gh api "repos/${NEW_GITHUB_REPO}/environments/production" &>/dev/null 2>&1; then
  info "Also setting secrets on 'production' environment..."
  echo "${PROVIDER_NAME}" | gh secret set WORKLOAD_IDENTITY_PROVIDER -R "${NEW_GITHUB_REPO}" -e production
  echo "${SA_EMAIL}"       | gh secret set GCP_SERVICE_ACCOUNT        -R "${NEW_GITHUB_REPO}" -e production
  success "production environment secrets set"
else
  warn "'production' environment not found on the new repo."
  echo "     Create it: Settings → Environments → New environment → name: production"
  echo "     Then run this script again (idempotent) or set the two secrets there manually."
fi

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Migration complete ✓${RESET}"
echo ""
echo "  New remote  : ${NEW_GIT_REMOTE}"
echo "  WIF provider: ${PROVIDER_NAME}"
echo "  CI/CD SA    : ${SA_EMAIL}"
echo ""
echo "Next steps:"
echo "  1. Open the new repo on GitHub and confirm the push:"
echo "       https://github.com/${NEW_GITHUB_REPO}"
echo ""
echo "  2. Trigger an infra-only Terraform run to verify CI/CD:"
echo "       gh workflow run terraform.yml -R ${NEW_GITHUB_REPO} \\"
echo "          --field action=apply"
echo ""
echo "  3. Then trigger a full image build + deploy:"
echo "       gh workflow run build-image.yml -R ${NEW_GITHUB_REPO}"
echo ""
