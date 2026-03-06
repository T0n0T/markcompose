#!/usr/bin/env bash
# shellcheck disable=SC2034

if [[ -n "${MARKCOMPOSE_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
MARKCOMPOSE_COMMON_SH_LOADED=1

MARKCOMPOSE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKCOMPOSE_SCRIPTS_DIR="$(cd "${MARKCOMPOSE_LIB_DIR}/.." && pwd)"
MARKCOMPOSE_REPO_ROOT="$(cd "${MARKCOMPOSE_SCRIPTS_DIR}/.." && pwd)"
MARKCOMPOSE_ENV_FILE="${MARKCOMPOSE_REPO_ROOT}/.env.runtime"
MARKCOMPOSE_BASELINE_ENV_FILE="${MARKCOMPOSE_REPO_ROOT}/.env"
MARKCOMPOSE_RUNTIME_DIR="${MARKCOMPOSE_REPO_ROOT}/.runtime"
MARKCOMPOSE_MARKWATCH_PID_FILE="${MARKCOMPOSE_REPO_ROOT}/.markwatch.pid"
MARKCOMPOSE_MARKWATCH_LOG_FILE="${MARKCOMPOSE_REPO_ROOT}/.markwatch.log"
MARKCOMPOSE_ENTRYPOINT="${MARKCOMPOSE_REPO_ROOT}/markcompose.sh"
MARKCOMPOSE_COMPOSE_PROJECT_NAME="${MARKCOMPOSE_COMPOSE_PROJECT_NAME:-markcompose}"
readonly MARKCOMPOSE_LIB_DIR MARKCOMPOSE_SCRIPTS_DIR MARKCOMPOSE_REPO_ROOT MARKCOMPOSE_ENV_FILE MARKCOMPOSE_BASELINE_ENV_FILE MARKCOMPOSE_RUNTIME_DIR MARKCOMPOSE_MARKWATCH_PID_FILE MARKCOMPOSE_MARKWATCH_LOG_FILE MARKCOMPOSE_ENTRYPOINT MARKCOMPOSE_COMPOSE_PROJECT_NAME

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly MC_COLOR_RESET=$'[0m'
  readonly MC_COLOR_BOLD=$'[1m'
  readonly MC_COLOR_BLUE=$'[38;5;39m'
  readonly MC_COLOR_GREEN=$'[38;5;42m'
  readonly MC_COLOR_YELLOW=$'[38;5;214m'
  readonly MC_COLOR_RED=$'[38;5;196m'
  readonly MC_COLOR_DIM=$'[2m'
else
  readonly MC_COLOR_RESET=''
  readonly MC_COLOR_BOLD=''
  readonly MC_COLOR_BLUE=''
  readonly MC_COLOR_GREEN=''
  readonly MC_COLOR_YELLOW=''
  readonly MC_COLOR_RED=''
  readonly MC_COLOR_DIM=''
fi

mc::die() {
  printf '%s✖ %s%s
' "${MC_COLOR_RED}${MC_COLOR_BOLD}" "$*" "${MC_COLOR_RESET}" >&2
  exit 1
}

mc::section() {
  local title="$1"
  printf '
%s━━ %s ━━%s
' "${MC_COLOR_BLUE}${MC_COLOR_BOLD}" "${title}" "${MC_COLOR_RESET}"
}

mc::step() {
  printf '%s→%s %s
' "${MC_COLOR_BLUE}${MC_COLOR_BOLD}" "${MC_COLOR_RESET}" "$*"
}

mc::info() {
  printf '%s•%s %s
' "${MC_COLOR_DIM}" "${MC_COLOR_RESET}" "$*"
}

mc::success() {
  printf '%s✓%s %s
' "${MC_COLOR_GREEN}${MC_COLOR_BOLD}" "${MC_COLOR_RESET}" "$*"
}

mc::warn() {
  printf '%s!%s %s
' "${MC_COLOR_YELLOW}${MC_COLOR_BOLD}" "${MC_COLOR_RESET}" "$*" >&2
}

mc::kv() {
  local key="$1"
  local value="$2"
  printf '  %s%-18s%s %s
' "${MC_COLOR_DIM}" "${key}:" "${MC_COLOR_RESET}" "${value}"
}

mc::require_cmd() {
  command -v "$1" >/dev/null 2>&1 || mc::die "Required command not found: $1"
}

mc::ensure_dir() {
  [[ -d "$1" ]] || mc::die "Directory not found: $1"
}

mc::ensure_dir_or_create() {
  [[ -d "$1" ]] || mkdir -p "$1"
}

mc::to_abs() {
  realpath "$1"
}

mc::check_no_spaces() {
  [[ ! "$1" =~ [[:space:]] ]] || mc::die "Path contains whitespace, which is unsupported: $1"
}

mc::check_num() {
  [[ "$1" =~ ^[0-9]+$ ]] || mc::die "$2 must be numeric: $1"
}

mc::check_port() {
  local port="$1"
  local name="${2:-port}"
  mc::check_num "${port}" "${name}"
  (( port >= 1 && port <= 65535 )) || mc::die "${name} must be in range 1..65535: ${port}"
}

mc::check_asset_dir() {
  local asset_dir="$1"

  [[ -n "${asset_dir}" ]] || mc::die "assets_dir must not be empty"
  [[ "${asset_dir}" != "." && "${asset_dir}" != ".." ]] || mc::die "assets_dir cannot be '.' or '..': ${asset_dir}"
  [[ "${asset_dir}" != */* ]] || mc::die "assets_dir must be a single folder name without '/': ${asset_dir}"
  [[ ! "${asset_dir}" =~ [[:space:]] ]] || mc::die "assets_dir contains whitespace, which is unsupported: ${asset_dir}"
}

mc::check_docker_compose() {
  docker compose version >/dev/null 2>&1 || mc::die "docker compose is not available"
}
