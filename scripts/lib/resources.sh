#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154

mc::resource::resolve_default_markwatch_package() {
  local -n out="$1"
  local host_os=""
  local host_arch=""
  local target=""

  host_os="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  host_arch="$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

  if [[ "${host_os}" != "linux" ]]; then
    mc::die "Default markwatch package only supports Linux hosts. Detected OS: ${host_os}. Use --use-custom-watcher."
  fi

  case "${host_arch}" in
    x86_64|amd64)
      target="x86_64-unknown-linux-gnu"
      ;;
    aarch64|arm64)
      target="aarch64-unknown-linux-gnu"
      ;;
    *)
      mc::die "Unsupported CPU arch for default markwatch package: ${host_arch}. Supported: amd64, arm64. Use --use-custom-watcher."
      ;;
  esac

  out[target]="${target}"
  out[url]="https://github.com/T0n0T/markwatch/releases/latest/download/markwatch-${target}.tar.gz"
  out[archive_path]="${MARKCOMPOSE_RUNTIME_DIR}/markwatch-${target}.tar.gz"
}

mc::resource::try_resolve_markflow_dist_dir() {
  local extracted_dir="$1"
  local dist_dir="${extracted_dir}/dist"
  local index_file=""

  if [[ -f "${dist_dir}/index.html" ]]; then
    printf '%s\n' "${dist_dir}"
    return 0
  fi

  index_file="$(find "${extracted_dir}" -maxdepth 5 -type f -path '*/dist/index.html' | head -n 1 || true)"
  [[ -n "${index_file}" ]] || return 1
  dirname "${index_file}"
}

mc::resource::resolve_markflow_dist_dir() {
  local extracted_dir="$1"
  local dist_dir=""

  dist_dir="$(mc::resource::try_resolve_markflow_dist_dir "${extracted_dir}" || true)"
  [[ -n "${dist_dir}" ]] || mc::die "Cannot find dist/index.html after preparing markflow archive: ${extracted_dir}"
  printf '%s\n' "${dist_dir}"
}

mc::resource::resolve_markwatch_binary_from_dir() {
  local dir_path="$1"
  local bin_path=""

  bin_path="$(find "${dir_path}" -maxdepth 8 -type f -path '*/bin/markwatch' | head -n 1 || true)"
  if [[ -z "${bin_path}" ]]; then
    bin_path="$(find "${dir_path}" -maxdepth 4 -type f -name markwatch | head -n 1 || true)"
  fi

  [[ -n "${bin_path}" ]] || return 1
  chmod +x "${bin_path}"
  printf '%s\n' "${bin_path}"
}
