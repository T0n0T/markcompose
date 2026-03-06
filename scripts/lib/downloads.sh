#!/usr/bin/env bash

mc::download::fetch() {
  local label="$1"
  local url="$2"
  local output="$3"

  mkdir -p "$(dirname "${output}")"
  mc::step "Downloading ${label}" >&2
  mc::kv "From" "${url}" >&2
  mc::kv "To" "${output}" >&2

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "${output}.tmp" "${url}" || mc::die "Download failed: ${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${output}.tmp" "${url}" || mc::die "Download failed: ${url}"
  else
    mc::die "Neither curl nor wget is available for downloading ${url}"
  fi

  mv "${output}.tmp" "${output}"
}

mc::download::resolve_or_fetch() {
  local label="$1"
  local file_path="$2"
  local url="$3"

  if [[ -f "${file_path}" ]]; then
    mc::info "Using cached ${label}: ${file_path}" >&2
    printf '%s\n' "${file_path}"
    return 0
  fi

  mc::download::fetch "${label}" "${url}" "${file_path}"
  printf '%s\n' "${file_path}"
}

mc::archive::extract_tgz() {
  local archive="$1"
  local target_dir="$2"

  rm -rf "${target_dir}"
  mkdir -p "${target_dir}"
  tar -xzf "${archive}" -C "${target_dir}"
}
