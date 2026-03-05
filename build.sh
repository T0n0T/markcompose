#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/.env.runtime}"
STAGING_DIR=""

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

collect_attachment_refs() {
  local output_dir="$1"

  rg --no-filename -o '/attachments/[^"'"'"' <>()]+' "${output_dir}" -g '*.html' 2>/dev/null \
    | sed -E 's/[?#].*$//' \
    | sort -u
}

gate_check_output() {
  local output_dir="$1"
  local attachments_dir="$2"
  local missing=0
  local ref=""

  [[ -f "${output_dir}/index.html" ]] || die "Gate failed: generated site does not contain index.html"

  while IFS= read -r ref; do
    [[ -n "${ref}" ]] || continue
    local rel="${ref#/attachments/}"
    local file_path="${attachments_dir%/}/${rel}"
    if [[ ! -f "${file_path}" ]]; then
      echo "GATE: missing attachment -> ${ref} (expected ${file_path})" >&2
      missing=$((missing + 1))
    fi
  done < <(collect_attachment_refs "${output_dir}")

  (( missing == 0 )) || die "Gate failed: ${missing} attachment reference(s) are missing on disk."
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
require_cmd rg
docker compose version >/dev/null 2>&1 || die "docker compose is not available"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

[[ -n "${ATTACHMENTS_DIR:-}" ]] || die "ATTACHMENTS_DIR is required in ${ENV_FILE}"
[[ -d "${ATTACHMENTS_DIR}" ]] || die "Attachments directory not found: ${ATTACHMENTS_DIR}"

trap cleanup EXIT
STAGING_DIR="$(mktemp -d /tmp/markcompose-build.XXXXXX)"

echo "Release build started (env: ${ENV_FILE})"
echo "  staging_dir=${STAGING_DIR}"
run_hugo_build_to_staging "$(id -u):$(id -g)"

echo "Running gate checks..."
gate_check_output "${STAGING_DIR}" "${ATTACHMENTS_DIR}"
echo "Gate checks passed."

echo "Publishing to hugo_public volume (replace + clean)..."
publish_staging_to_public
echo "Release publish completed."
