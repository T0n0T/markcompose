#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh"
# shellcheck source=scripts/lib/build_helpers.sh
source "${SCRIPT_DIR}/lib/build_helpers.sh"

BUILD_STAGING_DIR=""

cleanup() {
  if [[ -n "${BUILD_STAGING_DIR}" && -d "${BUILD_STAGING_DIR}" ]]; then
    rm -rf "${BUILD_STAGING_DIR}" 2>/dev/null || true
  fi
}

usage() {
  cat <<EOF
Usage:
  markcompose.sh build [env_file]

Default env file:
  ${MARKCOMPOSE_ENV_FILE}
EOF
}

main() {
  local env_file="${1:-${MARKCOMPOSE_ENV_FILE}}"
  local hugo_base_url=""
  local markdown_dir=""
  local adapter_script=""
  local adapter_out_dir=""
  local container_content_dir="/markdown"
  local -a container_extra_volumes=()

  if (( $# > 1 )); then
    usage
    mc::die "Expected zero or one argument: [env_file]"
  fi
  if [[ "${env_file}" == "-h" || "${env_file}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -f "${env_file}" ]] || mc::die "Env file not found: ${env_file}. Run 'markcompose.sh start ...' first."
  mc::require_cmd docker
  mc::check_docker_compose

  mc::section "Build 1/4 · Bootstrap Hugo workspace"
  mc::kv "Env file" "${env_file}"
  mc::build::init_hugo_site_if_missing
  mc::build::install_reusable_layouts
  mc::success "Reusable layouts synced into hugo-site/layouts."

  mc::env::load "${env_file}"
  hugo_base_url="${HUGO_BASE_URL:-http://127.0.0.1:${HOST_PORT:-8080}/}"
  markdown_dir="${MARKDOWN_DIR:?MARKDOWN_DIR is required in env file}"
  adapter_script="${ADAPTER_SCRIPT-}"
  adapter_out_dir="${ADAPTER_OUT_DIR:-${MC_BUILD_DEFAULT_ADAPTER_OUTPUT_DIR}}"

  trap cleanup EXIT
  BUILD_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/markcompose-build.XXXXXX")"

  mc::section "Build 2/4 · Prepare content"
  mc::kv "Base URL" "${hugo_base_url}"
  mc::kv "Staging" "${BUILD_STAGING_DIR}"
  if [[ -n "${adapter_script}" ]]; then
    adapter_script="$(mc::build::resolve_adapter_script_path "${adapter_script}")"
    mc::build::prepare_adapted_content_dir "${markdown_dir}" "${adapter_out_dir}" "${adapter_script}"
    container_content_dir="/content"
    container_extra_volumes=(-v "${adapter_out_dir}:/content:ro")
  else
    mc::info "Skipping content adaptation step because ADAPTER_SCRIPT is empty."
  fi

  mc::section "Build 3/4 · Render and verify"
  mc::build::run_hugo_build_to_staging     "${env_file}"     "${BUILD_STAGING_DIR}"     "$(id -u):$(id -g)"     "${container_content_dir}"     "${hugo_base_url}"     "${container_extra_volumes[@]}"
  mc::build::gate_check_output "${BUILD_STAGING_DIR}"
  mc::success "Gate checks passed. index.html is present."

  mc::section "Build 4/4 · Publish"
  mc::build::publish_staging_to_public "${env_file}" "${BUILD_STAGING_DIR}"
  mc::success "Release publish completed."
}

main "$@"
