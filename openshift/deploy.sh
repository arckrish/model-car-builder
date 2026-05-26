#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Model Car Builder — OpenShift Deploy & Build Script
#
# Creates secrets, applies the BuildConfig, and triggers builds that pull
# models from HuggingFace and push OCI "model car" images to Quay.
#
# All credentials are injected via environment variables so the same script
# works on any cluster without editing YAML.
#
# Required environment variables:
#   QUAY_REGISTRY   — Quay registry + namespace (e.g. quay.io/myuser)
#   QUAY_USERNAME   — Quay robot account or username
#   QUAY_PASSWORD   — Quay password or token
#   HF_TOKEN        — HuggingFace API token
#
# Optional:
#   NAMESPACE       — OpenShift project (default: current project)
#   BUILD_MEMORY    — Memory limit for builds (default: 16Gi)
#
# Usage:
#   ./deploy.sh setup                              — Create secrets + BuildConfig
#   ./deploy.sh build <model_repo> [image_tag]     — Trigger a build
#   ./deploy.sh all   <model_repo> [image_tag]     — Setup + build in one step
#   ./deploy.sh clean                              — Remove all created resources
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configuration ────────────────────────────────────────────────────────────

QUAY_REGISTRY="${QUAY_REGISTRY:-}"
QUAY_USERNAME="${QUAY_USERNAME:-}"
QUAY_PASSWORD="${QUAY_PASSWORD:-}"
HF_TOKEN="${HF_TOKEN:-}"
NAMESPACE="${NAMESPACE:-}"
BUILD_MEMORY="${BUILD_MEMORY:-16Gi}"

BC_NAME="model-car-builder"
HF_SECRET_NAME="hf-token"
QUAY_SECRET_NAME="quay-push-secret"

# ── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "Required environment variable ${name} is not set."
  fi
}

ns_flag() {
  if [[ -n "${NAMESPACE}" ]]; then
    echo "-n ${NAMESPACE}"
  fi
}

oc_cmd() {
  if [[ -n "${NAMESPACE}" ]]; then
    oc -n "${NAMESPACE}" "$@"
  else
    oc "$@"
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  setup                           Create secrets and apply BuildConfig
  build <model_repo> [image_tag]  Trigger a model car build
  all   <model_repo> [image_tag]  Setup + build in one step
  clean                           Remove all created resources

Environment variables:
  QUAY_REGISTRY   Quay registry + namespace (e.g. quay.io/myuser)
  QUAY_USERNAME   Quay robot account or username
  QUAY_PASSWORD   Quay password or token
  HF_TOKEN        HuggingFace API token
  NAMESPACE       OpenShift project (default: current project)
  BUILD_MEMORY    Memory limit for builds (default: 16Gi)

Examples:
  # One-time setup
  export QUAY_REGISTRY=quay.io/myuser
  export QUAY_USERNAME=myuser+robot
  export QUAY_PASSWORD=my-token
  export HF_TOKEN=hf_xxxxxxxxxxxx
  ./deploy.sh setup

  # Build a model
  ./deploy.sh build ibm-granite/granite-3.3-2b-instruct

  # Build with a custom image tag
  ./deploy.sh build ibm-granite/granite-3.3-2b-instruct v1.0

  # Setup + build in one step
  ./deploy.sh all ibm-granite/granite-3.3-2b-instruct
EOF
  exit 1
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_setup() {
  require_var QUAY_REGISTRY
  require_var QUAY_USERNAME
  require_var QUAY_PASSWORD
  require_var HF_TOKEN

  info "Setting up model car builder..."

  # Create or switch to namespace if specified
  if [[ -n "${NAMESPACE}" ]]; then
    if ! oc get project "${NAMESPACE}" &>/dev/null; then
      info "Creating project ${NAMESPACE}..."
      oc new-project "${NAMESPACE}" --display-name="Model Car Builds" || true
    fi
  fi

  # Create HuggingFace token secret
  info "Creating HuggingFace token secret (${HF_SECRET_NAME})..."
  oc_cmd delete secret "${HF_SECRET_NAME}" --ignore-not-found &>/dev/null
  oc_cmd create secret generic "${HF_SECRET_NAME}" \
    --from-literal=token="${HF_TOKEN}"

  # Create Quay push secret (docker-registry type for image push)
  info "Creating Quay push secret (${QUAY_SECRET_NAME})..."
  oc_cmd delete secret "${QUAY_SECRET_NAME}" --ignore-not-found &>/dev/null
  oc_cmd create secret docker-registry "${QUAY_SECRET_NAME}" \
    --docker-server="${QUAY_REGISTRY%%/*}" \
    --docker-username="${QUAY_USERNAME}" \
    --docker-password="${QUAY_PASSWORD}"

  # Link push secret to builder service account
  info "Linking push secret to builder service account..."
  oc_cmd secrets link builder "${QUAY_SECRET_NAME}"

  # Apply BuildConfig
  info "Applying BuildConfig (${BC_NAME})..."
  oc_cmd apply -f "${SCRIPT_DIR}/buildconfig.yaml"

  info "Setup complete. Run './deploy.sh build <model_repo>' to start a build."
}

cmd_build() {
  local model_repo="${1:-}"
  local image_tag="${2:-latest}"

  if [[ -z "${model_repo}" ]]; then
    die "Usage: $(basename "$0") build <model_repo> [image_tag]"
  fi

  require_var QUAY_REGISTRY

  # Derive image name from model repo: ibm-granite/granite-3.3-2b-instruct -> granite-3.3-2b-instruct
  local image_name
  image_name=$(basename "${model_repo}" | tr '[:upper:]' '[:lower:]')
  local full_image="${QUAY_REGISTRY}/${image_name}:${image_tag}"

  info "Building model car for: ${model_repo}"
  info "Target image: ${full_image}"

  # Patch BuildConfig output to target the correct Quay image
  oc_cmd patch bc/"${BC_NAME}" \
    --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/output/to/name\",\"value\":\"${full_image}\"}]"

  require_var HF_TOKEN

  # Start the build with model_repo and HF_TOKEN
  info "Starting build..."
  oc_cmd start-build "${BC_NAME}" \
    --build-arg="model_repo=${model_repo}" \
    --build-arg="HF_TOKEN=${HF_TOKEN}" \
    --follow

  info "Build complete. Image pushed to: ${full_image}"
}

cmd_clean() {
  info "Cleaning up model car builder resources..."
  oc_cmd delete bc/"${BC_NAME}" --ignore-not-found
  oc_cmd delete secret "${HF_SECRET_NAME}" --ignore-not-found
  oc_cmd delete secret "${QUAY_SECRET_NAME}" --ignore-not-found
  info "Cleanup complete."
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  setup)
    cmd_setup
    ;;
  build)
    cmd_build "${2:-}" "${3:-latest}"
    ;;
  all)
    cmd_setup
    cmd_build "${2:-}" "${3:-latest}"
    ;;
  clean)
    cmd_clean
    ;;
  *)
    usage
    ;;
esac
