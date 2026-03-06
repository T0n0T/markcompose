#!/usr/bin/env bash

mc::env::upsert_key() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp_file=""

  tmp_file="$(mktemp "${env_file}.upsert.XXXXXX")"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { replaced = 0 }
    {
      if ($0 ~ ("^[[:space:]]*(export[[:space:]]+)?" key "=")) {
        print key "=" value
        replaced = 1
      } else {
        print
      }
    }
    END {
      if (!replaced) {
        print key "=" value
      }
    }
  ' "${env_file}" > "${tmp_file}"
  mv "${tmp_file}" "${env_file}"
}

mc::env::write_runtime_file() {
  local baseline_env="$1"
  local output_env="$2"
  local markdown_dir="$3"
  local editor_dir="$4"
  local asset_dir="$5"
  local host_port="$6"
  local editor_port="$7"
  local adapter_script="$8"
  local compose_project_name="$9"
  local tmp_env=""

  tmp_env="$(mktemp "${output_env}.tmp.XXXXXX")"
  if [[ -f "${baseline_env}" ]]; then
    cp "${baseline_env}" "${tmp_env}"
  else
    : > "${tmp_env}"
  fi

  mc::env::upsert_key "${tmp_env}" "MARKDOWN_DIR" "${markdown_dir}"
  mc::env::upsert_key "${tmp_env}" "EDITOR_STATIC_DIR" "${editor_dir}"
  mc::env::upsert_key "${tmp_env}" "ASSETS_DIR" "${asset_dir}"
  mc::env::upsert_key "${tmp_env}" "ADAPTER_SCRIPT" "${adapter_script}"
  mc::env::upsert_key "${tmp_env}" "HOST_PORT" "${host_port}"
  mc::env::upsert_key "${tmp_env}" "EDITOR_PORT" "${editor_port}"
  mc::env::upsert_key "${tmp_env}" "COMPOSE_PROJECT_NAME" "${compose_project_name}"

  mv "${tmp_env}" "${output_env}"
}

mc::env::load() {
  local env_file="$1"
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}
