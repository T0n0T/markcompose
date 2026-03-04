#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/.env.runtime}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -f "${ENV_FILE}" ]] || die "Env file not found: ${ENV_FILE}. Run start.sh first."
docker compose version >/dev/null 2>&1 || die "docker compose is not available"

echo "Running Hugo build with env file: ${ENV_FILE}"
(
  cd "${SCRIPT_DIR}"
  docker compose --env-file "${ENV_FILE}" run --rm --no-deps hugo-builder
)
echo "Hugo build completed."
