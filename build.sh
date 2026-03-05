#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/.env.runtime}"
STAGING_DIR=""
HUGO_SITE_DIR="${SCRIPT_DIR}/hugo-site"
REUSABLE_MARKUP_DIR="${SCRIPT_DIR}/hugo-reuse/layouts/_markup"
HUGO_IMAGE="docker.io/hugomods/hugo:dart-sass-non-root"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup() {
  if [[ -n "${STAGING_DIR}" ]] && [[ -d "${STAGING_DIR}" ]]; then
    rm -rf "${STAGING_DIR}" 2>/dev/null || true
  fi
}

ensure_reusable_markup_templates() {
  [[ -f "${REUSABLE_MARKUP_DIR}/render-image.html" ]] || die "Reusable template not found: ${REUSABLE_MARKUP_DIR}/render-image.html"
  [[ -f "${REUSABLE_MARKUP_DIR}/render-link.html" ]] || die "Reusable template not found: ${REUSABLE_MARKUP_DIR}/render-link.html"
}

install_reusable_markup_templates() {
  mkdir -p "${HUGO_SITE_DIR}/layouts/_markup"
  cp "${REUSABLE_MARKUP_DIR}/render-image.html" "${HUGO_SITE_DIR}/layouts/_markup/render-image.html"
  cp "${REUSABLE_MARKUP_DIR}/render-link.html" "${HUGO_SITE_DIR}/layouts/_markup/render-link.html"
}

init_hugo_site_if_missing() {
  if [[ -d "${HUGO_SITE_DIR}" ]]; then
    return 0
  fi

  ensure_reusable_markup_templates
  echo "hugo-site not found. Initializing with Hugo image..."
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "${SCRIPT_DIR}:/work" \
    -w /work \
    "${HUGO_IMAGE}" \
    sh -lc 'hugo new site hugo-site'
  install_reusable_markup_templates
  echo "Initialized hugo-site and installed reusable render hooks."
}

gate_check_output() {
  local output_dir="$1"

  [[ -f "${output_dir}/index.html" ]] || die "Gate failed: generated site does not contain index.html"
}

run_hugo_build_to_staging() {
  local user_uid_gid="$1"
  local build_cmd='set -eu
hugo \
  --source /site \
  --contentDir /markdown \
  --destination /out \
  --cleanDestinationDir \
  --noBuildLock
chown -R '"${user_uid_gid}"' /out'

  (
    cd "${SCRIPT_DIR}"
    docker compose --env-file "${ENV_FILE}" run --rm --no-deps \
      -v "${STAGING_DIR}:/out" \
      hugo-builder \
      sh -lc "${build_cmd}"
  )
}

publish_staging_to_public() {
  local publish_cmd='set -eu
find /public -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a /staging/. /public/'

  (
    cd "${SCRIPT_DIR}"
    docker compose --env-file "${ENV_FILE}" run --rm --no-deps \
      -v "${STAGING_DIR}:/staging:ro" \
      hugo-builder \
      sh -lc "${publish_cmd}"
  )
}

[[ -f "${ENV_FILE}" ]] || die "Env file not found: ${ENV_FILE}. Run start.sh first."
require_cmd docker
docker compose version >/dev/null 2>&1 || die "docker compose is not available"
init_hugo_site_if_missing

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

trap cleanup EXIT
STAGING_DIR="$(mktemp -d /tmp/markcompose-build.XXXXXX)"

echo "Release build started (env: ${ENV_FILE})"
echo "  staging_dir=${STAGING_DIR}"
run_hugo_build_to_staging "$(id -u):$(id -g)"

echo "Running gate checks..."
gate_check_output "${STAGING_DIR}"
echo "Gate checks passed."

echo "Publishing to hugo_public volume (replace + clean)..."
publish_staging_to_public
echo "Release publish completed."
