#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/watcher.sh
source "${SCRIPT_DIR}/lib/watcher.sh"

usage() {
  cat <<'EOF'
Usage:
  markcompose.sh stop
  markcompose.sh stop -v

Options:
  -v    Stop and remove named volumes.
  -h    Show this message.
EOF
}

main() {
  local remove_volumes="false"
  local -a args=(down)

  if (( $# > 1 )); then
    usage
    exit 1
  fi

  if (( $# == 1 )); then
    case "$1" in
      -v)
        remove_volumes="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  fi

  mc::require_cmd docker
  mc::check_docker_compose

  if [[ "${remove_volumes}" == "true" ]]; then
    args+=(--volumes)
  fi

  mc::section "Stop services"
  (
    cd "${MARKCOMPOSE_REPO_ROOT}"
    if [[ -f "${MARKCOMPOSE_ENV_FILE}" ]]; then
      docker compose --env-file "${MARKCOMPOSE_ENV_FILE}" "${args[@]}"
    else
      mc::warn "${MARKCOMPOSE_ENV_FILE} not found. Trying to stop by compose defaults."
      docker compose "${args[@]}"
    fi
  )

  mc::watcher::stop_existing "${MARKCOMPOSE_MARKWATCH_PID_FILE}"
  mc::success "Services stopped."
}

main "$@"
