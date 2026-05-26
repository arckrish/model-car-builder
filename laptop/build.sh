#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Model Car Builder — Laptop / Local Build Script
#
# Builds a model car OCI image locally using podman (or docker) and optionally
# pushes it to a registry such as Quay.
#
# Required environment variables:
#   none — but HF_TOKEN is needed for gated/private Hugging Face models.
#
# Optional environment variables:
#   HF_TOKEN        HuggingFace API token (for gated/private models)
#   REGISTRY        Target registry + namespace (e.g. quay.io/youruser)
#   CONTAINER_TOOL  podman | docker  (default: auto-detect, prefers podman)
#
# Usage:
#   ./build.sh <model_repo> [image_tag]            Build a model car
#   ./build.sh <model_repo> [image_tag] --push     Build and push to REGISTRY
#
# Examples:
#   ./build.sh ibm-granite/granite-3.3-2b-instruct
#   ./build.sh RedHatAI/Qwen3-8B-FP8-dynamic v1.0
#   REGISTRY=quay.io/myuser ./build.sh RedHatAI/Qwen3-8B-FP8-dynamic latest --push
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <model_repo> [image_tag] [--push]

Arguments:
  model_repo   Hugging Face repo id (e.g. ibm-granite/granite-3.3-2b-instruct)
  image_tag    Image tag (default: latest)
  --push       Push the image to \$REGISTRY after building

Environment variables:
  HF_TOKEN        HuggingFace token (required for gated/private models)
  REGISTRY        Registry + namespace, e.g. quay.io/youruser (required for --push)
  CONTAINER_TOOL  podman | docker (default: auto-detect)

Examples:
  ./build.sh ibm-granite/granite-3.3-2b-instruct
  REGISTRY=quay.io/myuser ./build.sh RedHatAI/Qwen3-8B-FP8-dynamic latest --push
EOF
  exit 1
}

# ── Parse args ───────────────────────────────────────────────────────────────
MODEL_REPO="${1:-}"
[[ -z "${MODEL_REPO}" || "${MODEL_REPO}" == "-h" || "${MODEL_REPO}" == "--help" ]] && usage

IMAGE_TAG="latest"
DO_PUSH="false"
shift || true
for arg in "$@"; do
  case "${arg}" in
    --push) DO_PUSH="true" ;;
    *)      IMAGE_TAG="${arg}" ;;
  esac
done

# ── Detect container tool ────────────────────────────────────────────────────
CONTAINER_TOOL="${CONTAINER_TOOL:-}"
if [[ -z "${CONTAINER_TOOL}" ]]; then
  if command -v podman &>/dev/null; then
    CONTAINER_TOOL="podman"
  elif command -v docker &>/dev/null; then
    CONTAINER_TOOL="docker"
  else
    die "Neither podman nor docker found. Install one or set CONTAINER_TOOL."
  fi
fi
info "Using container tool: ${CONTAINER_TOOL}"

# ── Validate model repo id ───────────────────────────────────────────────────
if [[ ! "${MODEL_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  die "Invalid model repo id: '${MODEL_REPO}' (expected format: org/model-name)"
fi

# ── Derive image name ────────────────────────────────────────────────────────
IMAGE_NAME="$(basename "${MODEL_REPO}" | tr '[:upper:]' '[:lower:]')"
if [[ -n "${REGISTRY:-}" ]]; then
  FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
  FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
fi

info "Model repo:   ${MODEL_REPO}"
info "Target image: ${FULL_IMAGE}"

# ── Build ────────────────────────────────────────────────────────────────────
BUILD_ARGS=(--build-arg "model_repo=${MODEL_REPO}")

# Pass HF_TOKEN as a build secret when available (preferred over --build-arg,
# which would bake the token into image history).
SECRET_ARGS=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  info "HF_TOKEN detected — passing as build secret 'hf_token'."
  export HF_TOKEN
  SECRET_ARGS=(--secret "id=hf_token,env=HF_TOKEN")
else
  warn "HF_TOKEN not set — only public (ungated) models will download."
fi

info "Starting build (this can take several minutes for large models)..."
"${CONTAINER_TOOL}" build \
  "${BUILD_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  -t "${FULL_IMAGE}" \
  -f "${SCRIPT_DIR}/Containerfile" \
  "${REPO_ROOT}"

info "Build complete: ${FULL_IMAGE}"

# ── Push ─────────────────────────────────────────────────────────────────────
if [[ "${DO_PUSH}" == "true" ]]; then
  [[ -z "${REGISTRY:-}" ]] && die "--push requires REGISTRY to be set."
  info "Pushing ${FULL_IMAGE}..."
  "${CONTAINER_TOOL}" push "${FULL_IMAGE}"
  info "Pushed. Deploy in OpenShift AI with connection URI:"
  echo ""
  echo "    oci://${FULL_IMAGE}"
  echo ""
else
  info "Skipping push. To push later:"
  echo "    ${CONTAINER_TOOL} push ${FULL_IMAGE}"
fi
