#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.runtime"
MARKWATCH_PID_FILE="${SCRIPT_DIR}/.markwatch.pid"

usage() {
  cat <<'EOF'
Usage:
  stop.sh
  stop.sh -v

Options:
  -v    Stop and remove named volumes.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

WITH_VOLUMES="false"

if (( $# > 1 )); then
  usage
  exit 1
fi

if (( $# == 1 )); then
  case "$1" in
    -v)
      WITH_VOLUMES="true"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
fi

docker compose version >/dev/null 2>&1 || die "docker compose is not available"

ARGS=(down)
if [[ "${WITH_VOLUMES}" == "true" ]]; then
  ARGS+=(--volumes)
fi

(
  cd "${SCRIPT_DIR}"
  if [[ -f "${ENV_FILE}" ]]; then
    docker compose --env-file "${ENV_FILE}" "${ARGS[@]}"
  else
    echo "WARN: ${ENV_FILE} not found. Trying to stop by compose defaults." >&2
    docker compose "${ARGS[@]}"
  fi
)

if [[ -f "${MARKWATCH_PID_FILE}" ]]; then
  PID="$(cat "${MARKWATCH_PID_FILE}" 2>/dev/null || true)"
  rm -f "${MARKWATCH_PID_FILE}"
  if [[ "${PID}" =~ ^[0-9]+$ ]] && kill -0 "${PID}" 2>/dev/null; then
    echo "Stopping markwatch (PID ${PID})"
    kill "${PID}" 2>/dev/null || true
  fi
fi

echo "Services stopped."
