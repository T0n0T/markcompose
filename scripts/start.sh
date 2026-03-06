#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2178
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh"
# shellcheck source=scripts/lib/downloads.sh
source "${SCRIPT_DIR}/lib/downloads.sh"
# shellcheck source=scripts/lib/resources.sh
source "${SCRIPT_DIR}/lib/resources.sh"
# shellcheck source=scripts/lib/watcher.sh
source "${SCRIPT_DIR}/lib/watcher.sh"
# shellcheck source=scripts/lib/waline.sh
source "${SCRIPT_DIR}/lib/waline.sh"

readonly DEFAULT_MARKFLOW_URL="https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz"
readonly DEFAULT_MARKFLOW_ARCHIVE_PATH="${MARKCOMPOSE_RUNTIME_DIR}/markflow-dist.tar.gz"
readonly DEFAULT_WALINE_SQLITE_URL="https://raw.githubusercontent.com/walinejs/waline/main/assets/waline.sqlite"
readonly DEFAULT_WALINE_SQLITE_PATH="${MARKCOMPOSE_RUNTIME_DIR}/waline.sqlite"

usage() {
  cat <<'EOF'
Usage:
  markcompose.sh start [options] <markdown_dir>

Options:
  --use-custom-editor <dir>    Use custom editor static directory instead of bundled markflow dist.
  --use-custom-watcher <cmd>   Use custom watcher command string instead of bundled markwatch.
  --content-adapter <script>   Enable content adaptation using the given adapter script path.
  -a, --assets-dir <dir>       Asset folder name under markdown dir (default: _assets).
  -p, --host-port <port>       Host port (default: 8080).
  --editor-port <port>         Editor host port (default: 8081).
  --no-watch                   Do not start markwatch watcher.
  --debounce-ms <num>          markwatch debounce ms (default: 800, default watcher only).
  --reconcile-sec <num>        markwatch reconcile sec (default: 600, default watcher only).
  --watch-log-level <level>    markwatch log level (default: info, default watcher only).
  -h, --help                   Show this message.
EOF
}

set_defaults() {
  local -n cfg_ref="$1"
  cfg_ref=()
  cfg_ref[assets_dir]="_assets"
  cfg_ref[host_port]="8080"
  cfg_ref[editor_port]="8081"
  cfg_ref[debounce_ms]="800"
  cfg_ref[reconcile_sec]="600"
  cfg_ref[watch_log_level]="info"
  cfg_ref[compose_project_name]="${MARKCOMPOSE_COMPOSE_PROJECT_NAME}"
  cfg_ref[custom_editor]="false"
  cfg_ref[custom_watcher]="false"
  cfg_ref[watch_enabled]="true"
  cfg_ref[default_watcher]="false"
  cfg_ref[watch_status]="not-started"
  cfg_ref[editor_static_dir]=""
  cfg_ref[watcher_command]=""
  cfg_ref[adapter_script]=""
  cfg_ref[markdown_dir]=""
}

parse_args() {
  local -n cfg_ref="$1"
  shift
  local -a positional=()

  while (( $# > 0 )); do
    case "$1" in
      --use-custom-watcher)
        (( $# >= 2 )) || mc::die "--use-custom-watcher requires a command string"
        cfg_ref[custom_watcher]="true"
        cfg_ref[watcher_command]="$2"
        shift 2
        ;;
      --use-custom-editor)
        (( $# >= 2 )) || mc::die "--use-custom-editor requires a directory path"
        cfg_ref[custom_editor]="true"
        cfg_ref[editor_static_dir]="$2"
        shift 2
        ;;
      -a|--assets-dir)
        (( $# >= 2 )) || mc::die "$1 requires a folder name"
        cfg_ref[assets_dir]="$2"
        shift 2
        ;;
      --content-adapter)
        (( $# >= 2 )) || mc::die "--content-adapter requires a script path"
        [[ -n "$2" ]] || mc::die "--content-adapter requires a non-empty script path"
        cfg_ref[adapter_script]="$2"
        shift 2
        ;;
      -p|--host-port)
        (( $# >= 2 )) || mc::die "$1 requires a port number"
        cfg_ref[host_port]="$2"
        shift 2
        ;;
      --editor-port)
        (( $# >= 2 )) || mc::die "$1 requires a port number"
        cfg_ref[editor_port]="$2"
        shift 2
        ;;
      --no-watch)
        cfg_ref[watch_enabled]="false"
        shift
        ;;
      --debounce-ms)
        (( $# >= 2 )) || mc::die "--debounce-ms requires a number"
        cfg_ref[debounce_ms]="$2"
        shift 2
        ;;
      --reconcile-sec)
        (( $# >= 2 )) || mc::die "--reconcile-sec requires a number"
        cfg_ref[reconcile_sec]="$2"
        shift 2
        ;;
      --watch-log-level)
        (( $# >= 2 )) || mc::die "--watch-log-level requires a value"
        cfg_ref[watch_log_level]="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while (( $# > 0 )); do
          positional+=("$1")
          shift
        done
        ;;
      -*)
        mc::die "Unknown option: $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  (( ${#positional[@]} == 1 )) || {
    usage
    mc::die "Expected exactly one positional argument: <markdown_dir>"
  }
  cfg_ref[markdown_dir]="${positional[0]}"
}

validate_inputs() {
  local -n cfg_ref="$1"

  mc::section "Phase 1/6 · Validate inputs"
  mc::check_asset_dir "${cfg_ref[assets_dir]}"
  mc::check_num "${cfg_ref[debounce_ms]}" "debounce-ms"
  mc::check_num "${cfg_ref[reconcile_sec]}" "reconcile-sec"
  mc::check_port "${cfg_ref[host_port]}" "host_port"
  mc::check_port "${cfg_ref[editor_port]}" "editor_port"
  [[ "${cfg_ref[host_port]}" != "${cfg_ref[editor_port]}" ]] || mc::die "host_port and editor_port must be different"

  mc::require_cmd docker
  mc::require_cmd realpath
  mc::check_docker_compose
  if [[ "${cfg_ref[custom_editor]}" != "true" ]] || [[ "${cfg_ref[custom_watcher]}" != "true" && "${cfg_ref[watch_enabled]}" == "true" ]]; then
    mc::require_cmd tar
  fi
  mc::success "Input validation passed."
}

prepare_editor() {
  local -n cfg_ref="$1"
  local extract_dir=""
  local dist_dir=""
  local archive_path="${DEFAULT_MARKFLOW_ARCHIVE_PATH}"

  mc::section "Phase 2/6 · Prepare editor resources"
  if [[ "${cfg_ref[custom_editor]}" == "true" ]]; then
    mc::step "Using custom editor directory."
    return 0
  fi

  mc::step "Using bundled markflow editor package."
  extract_dir="${MARKCOMPOSE_RUNTIME_DIR}/markflow"
  if [[ -d "${extract_dir}" ]]; then
    dist_dir="$(mc::resource::try_resolve_markflow_dist_dir "${extract_dir}" || true)"
  fi

  if [[ -z "${dist_dir}" ]]; then
    mc::info "No usable extracted markflow dist found; preparing archive."
    archive_path="$(mc::download::resolve_or_fetch "markflow archive" "${archive_path}" "${DEFAULT_MARKFLOW_URL}")"
    archive_path="$(mc::to_abs "${archive_path}")"
    mc::archive::extract_tgz "${archive_path}" "${extract_dir}"
    dist_dir="$(mc::resource::resolve_markflow_dist_dir "${extract_dir}")"
  else
    mc::info "Using existing extracted markflow dist."
  fi

  cfg_ref[editor_static_dir]="${dist_dir}"
  mc::success "Editor assets ready."
}

prepare_watcher() {
  local -n cfg_ref="$1"
  local extract_dir=""
  local binary_path=""
  local archive_path=""
  local -A package=()

  mc::section "Phase 3/6 · Prepare watcher resources"
  if [[ "${cfg_ref[watch_enabled]}" != "true" ]]; then
    mc::info "Watcher disabled (--no-watch)."
    return 0
  fi
  if [[ "${cfg_ref[custom_watcher]}" == "true" ]]; then
    mc::step "Watcher enabled; using custom watcher command."
    return 0
  fi

  mc::step "Watcher enabled; using bundled markwatch package."
  mc::resource::resolve_default_markwatch_package package
  extract_dir="${MARKCOMPOSE_RUNTIME_DIR}/markwatch"
  archive_path="${package[archive_path]}"

  if [[ -d "${extract_dir}" ]]; then
    binary_path="$(mc::resource::resolve_markwatch_binary_from_dir "${extract_dir}" || true)"
    if [[ -n "${binary_path}" ]] && [[ "${binary_path}" != *"markwatch-${package[target]}"* ]]; then
      binary_path=""
    fi
  fi

  if [[ -z "${binary_path}" ]]; then
    mc::info "No usable extracted markwatch binary found; preparing archive."
    archive_path="$(mc::download::resolve_or_fetch "markwatch archive" "${archive_path}" "${package[url]}")"
    archive_path="$(mc::to_abs "${archive_path}")"
    mc::archive::extract_tgz "${archive_path}" "${extract_dir}"
    binary_path="$(mc::resource::resolve_markwatch_binary_from_dir "${extract_dir}" || true)"
    [[ -n "${binary_path}" ]] || mc::die "Cannot find markwatch binary after extracting default package"
  else
    mc::info "Using existing extracted markwatch binary."
  fi

  cfg_ref[watcher_command]="$(printf '%q' "${binary_path}")"
  cfg_ref[default_watcher]="true"
  mc::success "Watcher binary ready."
}

write_runtime_env() {
  local -n cfg_ref="$1"

  mc::section "Phase 4/6 · Prepare runtime configuration"
  mc::ensure_dir "${cfg_ref[markdown_dir]}"
  mc::ensure_dir_or_create "${cfg_ref[markdown_dir]}/${cfg_ref[assets_dir]}"
  if [[ "${cfg_ref[custom_editor]}" == "true" ]]; then
    mc::ensure_dir "${cfg_ref[editor_static_dir]}"
  else
    mc::ensure_dir_or_create "${cfg_ref[editor_static_dir]}"
  fi
  if [[ "${cfg_ref[watch_enabled]}" == "true" ]]; then
    [[ -n "${cfg_ref[watcher_command]//[[:space:]]/}" ]] || mc::die "watcher_command must not be empty"
  fi

  cfg_ref[markdown_dir]="$(mc::to_abs "${cfg_ref[markdown_dir]}")"
  cfg_ref[editor_static_dir]="$(mc::to_abs "${cfg_ref[editor_static_dir]}")"

  mc::check_no_spaces "${cfg_ref[markdown_dir]}"
  mc::check_no_spaces "${cfg_ref[editor_static_dir]}"
  if [[ -n "${cfg_ref[adapter_script]}" ]]; then
    mc::check_no_spaces "${cfg_ref[adapter_script]}"
  fi

  if [[ -f "${MARKCOMPOSE_BASELINE_ENV_FILE}" ]]; then
    mc::info "Using baseline env file: ${MARKCOMPOSE_BASELINE_ENV_FILE}"
  else
    mc::info "No baseline .env found; writing runtime env from defaults."
  fi

  mc::env::write_runtime_file     "${MARKCOMPOSE_BASELINE_ENV_FILE}"     "${MARKCOMPOSE_ENV_FILE}"     "${cfg_ref[markdown_dir]}"     "${cfg_ref[editor_static_dir]}"     "${cfg_ref[assets_dir]}"     "${cfg_ref[host_port]}"     "${cfg_ref[editor_port]}"     "${cfg_ref[adapter_script]}"     "${cfg_ref[compose_project_name]}"

  mc::env::load "${MARKCOMPOSE_ENV_FILE}"
  cfg_ref[effective_hugo_base_url]="${HUGO_BASE_URL:-http://127.0.0.1:${cfg_ref[host_port]}/}"

  mc::success "Runtime env file written."
  mc::kv "ENV_FILE" "${MARKCOMPOSE_ENV_FILE}"
  mc::kv "MARKDOWN_DIR" "${cfg_ref[markdown_dir]}"
  mc::kv "EDITOR_STATIC_DIR" "${cfg_ref[editor_static_dir]}"
  mc::kv "ASSETS_DIR" "${cfg_ref[assets_dir]}"
  mc::kv "ADAPTER_SCRIPT" "${cfg_ref[adapter_script]:-<disabled>}"
  mc::kv "Project" "${cfg_ref[compose_project_name]}"
  mc::kv "HOST_PORT" "${cfg_ref[host_port]}"
  mc::kv "EDITOR_PORT" "${cfg_ref[editor_port]}"
  mc::kv "HUGO_BASE_URL" "${cfg_ref[effective_hugo_base_url]}"
}

build_site() {
  mc::section "Phase 5/6 · Build site"
  mc::step "Running release build pipeline (markcompose.sh build)."
  "${MARKCOMPOSE_ENTRYPOINT}" build "${MARKCOMPOSE_ENV_FILE}"
}

start_services() {
  local -n cfg_ref="$1"
  local waline_seed_path=""

  mc::section "Phase 6/6 · Start services"
  if mc::waline::sqlite_exists_in_volume "${MARKCOMPOSE_ENV_FILE}"; then
    mc::info "Waline SQLite already exists in volume; keeping existing users/comments."
  else
    waline_seed_path="$(mc::download::resolve_or_fetch "waline sqlite seed" "${DEFAULT_WALINE_SQLITE_PATH}" "${DEFAULT_WALINE_SQLITE_URL}")"
    mc::waline::seed_volume_if_needed "${MARKCOMPOSE_ENV_FILE}" "${waline_seed_path}"
  fi

  mc::step "Starting waline and nginx containers."
  (
    cd "${MARKCOMPOSE_REPO_ROOT}"
    docker compose --env-file "${MARKCOMPOSE_ENV_FILE}" up -d --force-recreate waline nginx
  )

  if [[ "${cfg_ref[watch_enabled]}" == "true" ]]; then
    if [[ "${cfg_ref[default_watcher]}" != "true" ]]; then
      mc::warn "Custom watcher mode: --debounce-ms/--reconcile-sec/--watch-log-level are ignored."
    fi
    mc::step "Starting watcher process."
    if mc::watcher::start       "${cfg_ref[watcher_command]}"       "${cfg_ref[markdown_dir]}"       "${MARKCOMPOSE_ENTRYPOINT}"       "${MARKCOMPOSE_ENV_FILE}"       "${cfg_ref[default_watcher]}"       "${cfg_ref[debounce_ms]}"       "${cfg_ref[reconcile_sec]}"       "${cfg_ref[watch_log_level]}"       "${MARKCOMPOSE_REPO_ROOT}"       "${MARKCOMPOSE_MARKWATCH_PID_FILE}"       "${MARKCOMPOSE_MARKWATCH_LOG_FILE}"; then
      cfg_ref[watch_status]="started"
    else
      cfg_ref[watch_status]="failed"
    fi
  else
    cfg_ref[watch_status]="disabled"
  fi
}

print_summary() {
  local -n cfg_ref="$1"

  mc::section "Startup summary"
  mc::kv "Project" "${cfg_ref[compose_project_name]}"
  mc::kv "Blog" "http://127.0.0.1:${cfg_ref[host_port]}/"
  mc::kv "Editor" "http://127.0.0.1:${cfg_ref[editor_port]}/"
  mc::kv "Assets" "http://127.0.0.1:${cfg_ref[host_port]}/${cfg_ref[assets_dir]}/"
  mc::kv "HUGO_BASE_URL" "${cfg_ref[effective_hugo_base_url]}"
  mc::kv "Waline API" "http://127.0.0.1:${cfg_ref[host_port]}/waline/"
  mc::kv "Waline Admin" "http://127.0.0.1:${cfg_ref[host_port]}/waline/ui"

  case "${cfg_ref[watch_status]}" in
    started)
      mc::kv "Markwatch" "started (PID $(cat "${MARKCOMPOSE_MARKWATCH_PID_FILE}"))"
      mc::kv "Watch Log" "${MARKCOMPOSE_MARKWATCH_LOG_FILE}"
      ;;
    failed)
      mc::kv "Markwatch" "failed to stay running"
      mc::kv "Watch Log" "${MARKCOMPOSE_MARKWATCH_LOG_FILE}"
      ;;
    *)
      mc::kv "Markwatch" "disabled"
      ;;
  esac

  mc::success "Startup flow completed."
}

main() {
  local -A cfg=()
  set_defaults cfg
  parse_args cfg "$@"
  validate_inputs cfg
  prepare_editor cfg
  prepare_watcher cfg
  write_runtime_env cfg
  build_site
  start_services cfg
  print_summary cfg
}

main "$@"
