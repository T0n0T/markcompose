#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
ENV_FILE="${1:-${REPO_ROOT}/.env.runtime}"
STAGING_DIR=""
HUGO_SITE_DIR="${REPO_ROOT}/hugo-site"
REUSABLE_MARKUP_DIR="${REPO_ROOT}/hugo-reuse/layouts/_markup"
HUGO_IMAGE="docker.io/hugomods/hugo:dart-sass-non-root"
DEFAULT_ADAPTER_OUTPUT_DIR="${REPO_ROOT}/.runtime/content-adapted"

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
    -v "${REPO_ROOT}:/work" \
    -w /work \
    "${HUGO_IMAGE}" \
    sh -lc 'hugo new site hugo-site'
  install_reusable_markup_templates
  echo "Initialized hugo-site and installed reusable render hooks."
}

gate_check_output() {
  local generated_site_dir="$1"

  [[ -f "${generated_site_dir}/index.html" ]] || die "Gate failed: generated site does not contain index.html"
}

prepare_adapted_content_dir() {
  local input_dir="$1"
  local adapted_output_dir="$2"
  local adapter_script="$3"

  [[ -x "${adapter_script}" ]] || die "Adapter script not found or not executable: ${adapter_script}"

  rm -rf "${adapted_output_dir}" 2>/dev/null || true
  mkdir -p "$(dirname "${adapted_output_dir}")"

  echo "Preparing adapted content..."
  echo "  input_dir=${input_dir}"
  echo "  output_dir=${adapted_output_dir}"
  "${adapter_script}" "${input_dir}" "${adapted_output_dir}"
}

resolve_adapter_script_path() {
  local script_path="$1"
  if [[ "${script_path}" == /* ]]; then
    echo "${script_path}"
    return 0
  fi
  echo "${REPO_ROOT}/${script_path}"
}

run_hugo_build_to_staging() {
  local owner_uid_gid="$1"
  local container_content_dir="$2"
  shift 2

  # Keep the build command as a single string for `sh -lc`.
  # Note: HUGO_ASSETS_DIR is provided by docker-compose.yml (defaults to "_assets").
  local build_cmd
  build_cmd="$(cat <<EOF
set -eu
hugo \\
  --source /site \\
  --contentDir ${container_content_dir} \\
  --destination /out \\
  --cleanDestinationDir \\
  --noBuildLock

# Copy markdown-managed assets into output so Nginx can serve /<assets_dir>/...
if [ -n "\${HUGO_ASSETS_DIR:-}" ] && [ -d "/markdown/\${HUGO_ASSETS_DIR}" ]; then
  mkdir -p "/out/\${HUGO_ASSETS_DIR}"
  cp -a "/markdown/\${HUGO_ASSETS_DIR}/." "/out/\${HUGO_ASSETS_DIR}/"
fi

chown -R ${owner_uid_gid} /out
EOF
)"

  (
    cd "${REPO_ROOT}"
    docker compose --env-file "${ENV_FILE}" run --rm --no-deps \
      -v "${STAGING_DIR}:/out" \
      "$@" \
      hugo-builder \
      sh -lc "${build_cmd}"
  )
}

publish_staging_to_public() {
  local publish_cmd='set -eu
find /public -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a /staging/. /public/

# Ensure nginx can traverse/read published site content.
chmod 755 /public
find /public -type d -exec chmod 755 {} +
find /public -type f -exec chmod 644 {} +'

  (
    cd "${REPO_ROOT}"
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

ADAPTER_SCRIPT="${ADAPTER_SCRIPT-}"
ADAPTER_OUT_DIR="${ADAPTER_OUT_DIR:-${DEFAULT_ADAPTER_OUTPUT_DIR}}"

CONTAINER_CONTENT_DIR="/markdown"
CONTAINER_EXTRA_VOLUMES=()
if [[ -n "${ADAPTER_SCRIPT}" ]]; then
  ADAPTER_SCRIPT="$(resolve_adapter_script_path "${ADAPTER_SCRIPT}")"
  prepare_adapted_content_dir "${MARKDOWN_DIR}" "${ADAPTER_OUT_DIR}" "${ADAPTER_SCRIPT}"
  CONTAINER_CONTENT_DIR="/content"
  CONTAINER_EXTRA_VOLUMES=(-v "${ADAPTER_OUT_DIR}:/content:ro")
else
  echo "Skipping content adaptation step (ADAPTER_SCRIPT is empty)."
fi

run_hugo_build_to_staging "$(id -u):$(id -g)" "${CONTAINER_CONTENT_DIR}" "${CONTAINER_EXTRA_VOLUMES[@]}"

echo "Running gate checks..."
gate_check_output "${STAGING_DIR}"
echo "Gate checks passed."

echo "Publishing to hugo_public volume (replace + clean)..."
publish_staging_to_public
echo "Release publish completed."
