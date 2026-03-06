#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  markcompose.sh <command> [args]

Commands:
  start   Start services, build once, and optionally run watcher
  build   Run the release build pipeline
  stop    Stop services
  help    Show this message

Examples:
  ./markcompose.sh start <markdown_path>
  ./markcompose.sh start --content-adapter adapter/prepare_content.sh <markdown_path>
  ./markcompose.sh build
  ./markcompose.sh stop
EOF
}

main() {
  local command="${1:-help}"
  case "${command}" in
    start)
      shift
      exec "${SCRIPT_DIR}/start.sh" "$@"
      ;;
    build)
      shift
      exec "${SCRIPT_DIR}/build.sh" "$@"
      ;;
    stop)
      shift
      exec "${SCRIPT_DIR}/stop.sh" "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage
      printf '
Unknown command: %s
' "${command}" >&2
      exit 1
      ;;
  esac
}

main "$@"
