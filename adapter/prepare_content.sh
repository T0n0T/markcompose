#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  adapter/prepare_content.sh <input_dir> <output_dir> [config_toml]

Environment:
  ASSETS_DIR  Name of the asset directory under <input_dir> to ignore (default: _assets)
EOF
}

if (( $# < 2 || $# > 3 )); then
  usage
  exit 2
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"
CONFIG_PATH="${3:-${SCRIPT_DIR}/content-adapter.toml}"

exec python3 "${SCRIPT_DIR}/content_adapter.py" "${INPUT_DIR}" "${OUTPUT_DIR}" "${CONFIG_PATH}"
