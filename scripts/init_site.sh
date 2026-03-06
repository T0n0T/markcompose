#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/build_helpers.sh
source "${SCRIPT_DIR}/lib/build_helpers.sh"

usage() {
  cat <<EOF
Usage:
  markcompose.sh init-site

Initialize ./hugo-site for first-time setup.

Behavior:
  - If ./hugo-site/hugo.toml is missing, bootstrap site files with the Hugo Docker image.
  - If ./hugo-site/hugo.toml already exists, do not overwrite the site; just sync reusable layouts.
EOF
}

main() {
  if (( $# > 1 )); then
    usage
    mc::die "Expected zero arguments."
  fi
  if (( $# == 1 )); then
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        usage
        mc::die "Unknown argument: $1"
        ;;
    esac
  fi

  mc::require_cmd docker
  mc::section "Init Hugo site"
  mc::kv "Target" "${MC_BUILD_HUGO_SITE_DIR}"
  mc::build::init_hugo_site
  mc::info "You can now edit ./hugo-site/hugo.toml before running './markcompose.sh start ...'."
}

main "$@"
