#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.runtime"
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"
MARKWATCH_PID_FILE="${SCRIPT_DIR}/.markwatch.pid"
MARKWATCH_LOG_FILE="${SCRIPT_DIR}/.markwatch.log"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"

DEFAULT_MARKFLOW_URL="https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz"
DEFAULT_MARKWATCH_BASE_URL="https://github.com/T0n0T/markwatch/releases/latest/download"
DEFAULT_MARKWATCH_URL=""
DEFAULT_MARKWATCH_TARGET=""
DEFAULT_MARKFLOW_ARCHIVE_PATH="${RUNTIME_DIR}/markflow-dist.tar.gz"
DEFAULT_MARKWATCH_ARCHIVE_PATH=""

usage() {
  cat <<'USAGE'
Usage:
  start.sh [options] <markdown_dir>

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

Examples:
  ./start.sh /data/blog/md
  ./start.sh --content-adapter content-adapter/prepare_content.sh /data/blog/md
  ./start.sh --use-custom-watcher "markwatch --some-flag value" /data/blog/md
  ./start.sh --use-custom-editor /data/editor/dist -p 8080 --editor-port 8081 /data/blog/md
  ./start.sh --assets-dir images /data/blog/md
  ./start.sh --use-custom-editor /data/editor/dist --use-custom-watcher "markwatch" -p 8080 --editor-port 8081 /data/blog/md
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ensure_dir() {
  local path="$1"
  [[ -d "${path}" ]] || die "Directory not found: ${path}"
}

ensure_dir_or_create() {
  local path="$1"
  [[ -d "${path}" ]] || mkdir -p "${path}"
}

to_abs() {
  local path="$1"
  realpath "${path}"
}

check_no_spaces() {
  local value="$1"
  if [[ "${value}" =~ [[:space:]] ]]; then
    die "Path contains whitespace, which is unsupported by this script: ${value}"
  fi
}

check_num() {
  local value="$1"
  local name="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} must be numeric: ${value}"
}

check_port() {
  local port="$1"
  local name="${2:-port}"
  check_num "${port}" "${name}"
  (( port >= 1 && port <= 65535 )) || die "${name} must be in range 1..65535: ${port}"
}

check_asset_dir() {
  local asset_dir="$1"

  [[ -n "${asset_dir}" ]] || die "assets_dir must not be empty"
  [[ "${asset_dir}" != "." && "${asset_dir}" != ".." ]] || die "assets_dir cannot be '.' or '..': ${asset_dir}"
  [[ "${asset_dir}" != */* ]] || die "assets_dir must be a single folder name without '/': ${asset_dir}"
  if [[ "${asset_dir}" =~ [[:space:]] ]]; then
    die "assets_dir contains whitespace, which is unsupported: ${asset_dir}"
  fi
}

check_docker_compose() {
  docker compose version >/dev/null 2>&1 || die "docker compose is not available"
}

resolve_default_markwatch_package() {
  local host_os=""
  local host_arch=""
  local target=""

  host_os="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  host_arch="$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

  if [[ "${host_os}" != "linux" ]]; then
    die "Default markwatch package only supports Linux hosts. Detected OS: ${host_os}. Use --use-custom-watcher."
  fi

  case "${host_arch}" in
    x86_64|amd64)
      target="x86_64-unknown-linux-gnu"
      ;;
    aarch64|arm64)
      target="aarch64-unknown-linux-gnu"
      ;;
    *)
      die "Unsupported CPU arch for default markwatch package: ${host_arch}. Supported: amd64, arm64. Use --use-custom-watcher."
      ;;
  esac

  DEFAULT_MARKWATCH_TARGET="${target}"
  DEFAULT_MARKWATCH_URL="${DEFAULT_MARKWATCH_BASE_URL}/markwatch-${target}.tar.gz"
  DEFAULT_MARKWATCH_ARCHIVE_PATH="${RUNTIME_DIR}/markwatch-${target}.tar.gz"
}

write_env_file() {
  local markdown_dir="$1"
  local editor_dir="$2"
  local asset_dir="$3"
  local host_port="$4"
  local editor_port="$5"
  local adapter_script="$6"

  cat >"${ENV_FILE}" <<ENV
MARKDOWN_DIR=${markdown_dir}
EDITOR_STATIC_DIR=${editor_dir}
ASSETS_DIR=${asset_dir}
ADAPTER_SCRIPT=${adapter_script}
HOST_PORT=${host_port}
EDITOR_PORT=${editor_port}
COMPOSE_PROJECT_NAME=markcompose
ENV
}

download_archive() {
  local url="$1"
  local output="$2"

  mkdir -p "$(dirname "${output}")"
  echo "Downloading ${url} -> ${output}" >&2

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "${output}.tmp" "${url}" || die "Download failed: ${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${output}.tmp" "${url}" || die "Download failed: ${url}"
  else
    die "Neither curl nor wget is available for downloading ${url}"
  fi

  mv "${output}.tmp" "${output}"
}

resolve_or_download_archive() {
  local name="$1"
  local archive_path="$2"
  local url="$3"

  if [[ -f "${archive_path}" ]]; then
    echo "Using local ${name} archive: ${archive_path}" >&2
    echo "${archive_path}"
    return 0
  fi

  download_archive "${url}" "${archive_path}"
  echo "${archive_path}"
}

extract_tarball() {
  local archive="$1"
  local target_dir="$2"
  rm -rf "${target_dir}"
  mkdir -p "${target_dir}"
  tar -xzf "${archive}" -C "${target_dir}"
}

try_resolve_markflow_dist_dir() {
  local extracted_dir="$1"
  local dist_dir=""
  local index_file=""

  dist_dir="${extracted_dir}/dist"
  if [[ -f "${dist_dir}/index.html" ]]; then
    echo "${dist_dir}"
    return 0
  fi

  index_file="$(find "${extracted_dir}" -maxdepth 5 -type f -path "*/dist/index.html" | head -n 1 || true)"
  [[ -n "${index_file}" ]] || return 1
  dirname "${index_file}"
}

resolve_markflow_dist_dir() {
  local extracted_dir="$1"
  local dist_dir=""

  dist_dir="$(try_resolve_markflow_dist_dir "${extracted_dir}" || true)"
  [[ -n "${dist_dir}" ]] || die "Cannot find dist/index.html after preparing markflow archive: ${extracted_dir}"
  echo "${dist_dir}"
}

resolve_markwatch_binary_from_dir() {
  local dir_path="$1"
  local bin_path=""

  bin_path="$(find "${dir_path}" -maxdepth 8 -type f -path "*/bin/markwatch" | head -n 1 || true)"
  if [[ -z "${bin_path}" ]]; then
    bin_path="$(find "${dir_path}" -maxdepth 4 -type f -name markwatch | head -n 1 || true)"
  fi

  [[ -n "${bin_path}" ]] || return 1
  chmod +x "${bin_path}"
  echo "${bin_path}"
}

stop_existing_markwatch() {
  local existing_pid=""
  local wait_attempt=0

  if [[ ! -f "${MARKWATCH_PID_FILE}" ]]; then
    return 0
  fi

  existing_pid="$(cat "${MARKWATCH_PID_FILE}" 2>/dev/null || true)"
  rm -f "${MARKWATCH_PID_FILE}"

  [[ "${existing_pid}" =~ ^[0-9]+$ ]] || return 0
  if ! kill -0 "${existing_pid}" 2>/dev/null; then
    return 0
  fi

  echo "Stopping existing markwatch process (PID ${existing_pid})"
  kill "${existing_pid}" 2>/dev/null || true
  for (( wait_attempt = 0; wait_attempt < 20; wait_attempt++ )); do
    if ! kill -0 "${existing_pid}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  kill -9 "${existing_pid}" 2>/dev/null || true
}

start_markwatch() {
  local watcher_command="$1"
  local markdown_dir="$2"
  local default_watcher_enabled="$3"
  local debounce_ms="$4"
  local reconcile_sec="$5"
  local watch_log_level="$6"
  local build_command=""
  local run_command=""
  local watcher_pid=""

  stop_existing_markwatch
  touch "${MARKWATCH_LOG_FILE}"
  build_command="$(printf '%q' "${BUILD_SCRIPT}") $(printf '%q' "${ENV_FILE}")"

  run_command="${watcher_command} --root $(printf '%q' "${markdown_dir}") --workdir $(printf '%q' "${SCRIPT_DIR}") --cmd $(printf '%q' "${build_command}") --shell sh"
  if [[ "${default_watcher_enabled}" == "true" ]]; then
    run_command="${run_command} --debounce-ms $(printf '%q' "${debounce_ms}") --reconcile-sec $(printf '%q' "${reconcile_sec}") --log-level $(printf '%q' "${watch_log_level}")"
  fi

  (
    cd "${SCRIPT_DIR}"
    nohup bash -lc "${run_command}" >>"${MARKWATCH_LOG_FILE}" 2>&1 &
    echo $! >"${MARKWATCH_PID_FILE}"
  )

  watcher_pid="$(cat "${MARKWATCH_PID_FILE}" 2>/dev/null || true)"
  if [[ -z "${watcher_pid}" ]] || ! kill -0 "${watcher_pid}" 2>/dev/null; then
    echo "WARN: markwatch failed to start; check log: ${MARKWATCH_LOG_FILE}" >&2
    rm -f "${MARKWATCH_PID_FILE}"
    return 1
  fi

  sleep 1
  if ! kill -0 "${watcher_pid}" 2>/dev/null; then
    echo "WARN: markwatch exited right after startup; check log: ${MARKWATCH_LOG_FILE}" >&2
    rm -f "${MARKWATCH_PID_FILE}"
    return 1
  fi

  return 0
}

CUSTOM_WATCHER_ENABLED="false"
CUSTOM_EDITOR_ENABLED="false"
WATCH_DISABLED="false"
DEBOUNCE_MS="800"
RECONCILE_SEC="600"
WATCH_LOG_LEVEL="info"
MARKFLOW_ARCHIVE_PATH="${DEFAULT_MARKFLOW_ARCHIVE_PATH}"
WATCHER_ARCHIVE_PATH=""
POSITIONAL_ARGS=()
EDITOR_STATIC_DIR=""
WATCHER_COMMAND=""
ASSETS_DIR=""
ADAPTER_SCRIPT_PATH=""
HOST_PORT="8080"
EDITOR_PORT="8081"

while (( $# > 0 )); do
  case "$1" in
    --use-custom-watcher)
      (( $# >= 2 )) || die "--use-custom-watcher requires a command string"
      CUSTOM_WATCHER_ENABLED="true"
      WATCHER_COMMAND="$2"
      shift 2
      ;;
    --use-custom-editor)
      (( $# >= 2 )) || die "--use-custom-editor requires a directory path"
      CUSTOM_EDITOR_ENABLED="true"
      EDITOR_STATIC_DIR="$2"
      shift 2
      ;;
    -a|--assets-dir)
      (( $# >= 2 )) || die "$1 requires a folder name"
      ASSETS_DIR="$2"
      shift 2
      ;;
    --content-adapter)
      (( $# >= 2 )) || die "--content-adapter requires a script path"
      [[ -n "$2" ]] || die "--content-adapter requires a non-empty script path"
      ADAPTER_SCRIPT_PATH="$2"
      shift 2
      ;;
    -p|--host-port)
      (( $# >= 2 )) || die "$1 requires a port number"
      HOST_PORT="$2"
      shift 2
      ;;
    --editor-port)
      (( $# >= 2 )) || die "$1 requires a port number"
      EDITOR_PORT="$2"
      shift 2
      ;;
    --no-watch)
      WATCH_DISABLED="true"
      shift
      ;;
    --debounce-ms)
      (( $# >= 2 )) || die "--debounce-ms requires a number"
      DEBOUNCE_MS="$2"
      shift 2
      ;;
    --reconcile-sec)
      (( $# >= 2 )) || die "--reconcile-sec requires a number"
      RECONCILE_SEC="$2"
      shift 2
      ;;
    --watch-log-level)
      (( $# >= 2 )) || die "--watch-log-level requires a value"
      WATCH_LOG_LEVEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while (( $# > 0 )); do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

MARKDOWN_DIR=""
WATCHER_ENABLED="false"
WATCHER_BINARY_PATH=""
MARKWATCH_STATUS="not-started"
DEFAULT_WATCHER_ENABLED="false"

if [[ "${WATCH_DISABLED}" != "true" ]]; then
  WATCHER_ENABLED="true"
fi

if (( $# != 1 )); then
  usage
  die "Expected exactly one positional argument: <markdown_dir>"
fi

MARKDOWN_DIR="$1"
if [[ -z "${ASSETS_DIR}" ]]; then
  ASSETS_DIR="_assets"
fi

check_asset_dir "${ASSETS_DIR}"
check_num "${DEBOUNCE_MS}" "debounce-ms"
check_num "${RECONCILE_SEC}" "reconcile-sec"
check_port "${HOST_PORT}" "host_port"
check_port "${EDITOR_PORT}" "editor_port"
[[ "${HOST_PORT}" != "${EDITOR_PORT}" ]] || die "host_port and editor_port must be different"
check_docker_compose

if [[ "${CUSTOM_EDITOR_ENABLED}" != "true" ]] || { [[ "${CUSTOM_WATCHER_ENABLED}" != "true" ]] && [[ "${WATCHER_ENABLED}" == "true" ]]; }; then
  require_cmd tar
fi

if [[ "${CUSTOM_EDITOR_ENABLED}" != "true" ]]; then
  MARKFLOW_EXTRACT_DIR_PATH="${RUNTIME_DIR}/markflow"
  MARKFLOW_DIST_DIR_PATH=""

  if [[ -d "${MARKFLOW_EXTRACT_DIR_PATH}" ]]; then
    MARKFLOW_DIST_DIR_PATH="$(try_resolve_markflow_dist_dir "${MARKFLOW_EXTRACT_DIR_PATH}" || true)"
  fi

  if [[ -z "${MARKFLOW_DIST_DIR_PATH}" ]]; then
    MARKFLOW_ARCHIVE_PATH="$(resolve_or_download_archive "markflow" "${MARKFLOW_ARCHIVE_PATH}" "${DEFAULT_MARKFLOW_URL}")"
    MARKFLOW_ARCHIVE_PATH="$(to_abs "${MARKFLOW_ARCHIVE_PATH}")"
    extract_tarball "${MARKFLOW_ARCHIVE_PATH}" "${MARKFLOW_EXTRACT_DIR_PATH}"
    MARKFLOW_DIST_DIR_PATH="$(resolve_markflow_dist_dir "${MARKFLOW_EXTRACT_DIR_PATH}")"
  else
    echo "Using existing extracted markflow dist: ${MARKFLOW_DIST_DIR_PATH}" >&2
  fi

  EDITOR_STATIC_DIR="${MARKFLOW_DIST_DIR_PATH}"
fi

if [[ "${WATCHER_ENABLED}" == "true" ]] && [[ "${CUSTOM_WATCHER_ENABLED}" != "true" ]]; then
  resolve_default_markwatch_package
  WATCHER_ARCHIVE_PATH="${DEFAULT_MARKWATCH_ARCHIVE_PATH}"
  WATCHER_EXTRACT_DIR="${RUNTIME_DIR}/markwatch"
  WATCHER_BINARY_PATH=""

  if [[ -d "${WATCHER_EXTRACT_DIR}" ]]; then
    WATCHER_BINARY_PATH="$(resolve_markwatch_binary_from_dir "${WATCHER_EXTRACT_DIR}" || true)"
    if [[ -n "${WATCHER_BINARY_PATH}" ]] && [[ "${WATCHER_BINARY_PATH}" != *"markwatch-${DEFAULT_MARKWATCH_TARGET}"* ]]; then
      WATCHER_BINARY_PATH=""
    fi
  fi

  if [[ -z "${WATCHER_BINARY_PATH}" ]]; then
    WATCHER_ARCHIVE_PATH="$(resolve_or_download_archive "markwatch" "${WATCHER_ARCHIVE_PATH}" "${DEFAULT_MARKWATCH_URL}")"
    WATCHER_ARCHIVE_PATH="$(to_abs "${WATCHER_ARCHIVE_PATH}")"
    extract_tarball "${WATCHER_ARCHIVE_PATH}" "${WATCHER_EXTRACT_DIR}"
    WATCHER_BINARY_PATH="$(resolve_markwatch_binary_from_dir "${WATCHER_EXTRACT_DIR}" || true)"
    [[ -n "${WATCHER_BINARY_PATH}" ]] || die "Cannot find markwatch binary after extracting default package"
  else
    echo "Using existing extracted markwatch binary: ${WATCHER_BINARY_PATH}" >&2
  fi

  WATCHER_COMMAND="$(printf '%q' "${WATCHER_BINARY_PATH}")"
  DEFAULT_WATCHER_ENABLED="true"
fi

ensure_dir "${MARKDOWN_DIR}"
ensure_dir_or_create "${MARKDOWN_DIR}/${ASSETS_DIR}"
if [[ "${CUSTOM_EDITOR_ENABLED}" == "true" ]]; then
  ensure_dir "${EDITOR_STATIC_DIR}"
else
  ensure_dir_or_create "${EDITOR_STATIC_DIR}"
fi
if [[ "${WATCHER_ENABLED}" == "true" ]]; then
  [[ -n "${WATCHER_COMMAND//[[:space:]]/}" ]] || die "watcher_command must not be empty"
fi

MARKDOWN_DIR="$(to_abs "${MARKDOWN_DIR}")"
EDITOR_STATIC_DIR="$(to_abs "${EDITOR_STATIC_DIR}")"

check_no_spaces "${MARKDOWN_DIR}"
check_no_spaces "${EDITOR_STATIC_DIR}"
if [[ -n "${ADAPTER_SCRIPT_PATH}" ]]; then
  check_no_spaces "${ADAPTER_SCRIPT_PATH}"
fi

write_env_file "${MARKDOWN_DIR}" "${EDITOR_STATIC_DIR}" "${ASSETS_DIR}" "${HOST_PORT}" "${EDITOR_PORT}" "${ADAPTER_SCRIPT_PATH}"

echo "Configuration written to ${ENV_FILE}"
echo "  MARKDOWN_DIR=${MARKDOWN_DIR}"
echo "  EDITOR_STATIC_DIR=${EDITOR_STATIC_DIR}"
echo "  ASSETS_DIR=${ASSETS_DIR}"
if [[ -n "${ADAPTER_SCRIPT_PATH}" ]]; then
  echo "  ADAPTER_SCRIPT=${ADAPTER_SCRIPT_PATH}"
else
  echo "  ADAPTER_SCRIPT=<disabled>"
fi
echo "  HOST_PORT=${HOST_PORT}"
echo "  EDITOR_PORT=${EDITOR_PORT}"

"${BUILD_SCRIPT}" "${ENV_FILE}"

(
  cd "${SCRIPT_DIR}"
  docker compose --env-file "${ENV_FILE}" up -d nginx
)

if [[ "${WATCHER_ENABLED}" == "true" ]]; then
  if [[ "${DEFAULT_WATCHER_ENABLED}" != "true" ]]; then
    echo "Custom watcher mode: --debounce-ms/--reconcile-sec/--watch-log-level are ignored."
  fi
  if start_markwatch "${WATCHER_COMMAND}" "${MARKDOWN_DIR}" "${DEFAULT_WATCHER_ENABLED}" "${DEBOUNCE_MS}" "${RECONCILE_SEC}" "${WATCH_LOG_LEVEL}"; then
    MARKWATCH_STATUS="started"
  else
    MARKWATCH_STATUS="failed"
  fi
fi

echo "Service started:"
echo "  Blog:        http://127.0.0.1:${HOST_PORT}/"
echo "  Editor:      http://127.0.0.1:${EDITOR_PORT}/"
echo "  Assets:      http://127.0.0.1:${HOST_PORT}/${ASSETS_DIR}/"
if [[ "${MARKWATCH_STATUS}" == "started" ]]; then
  echo "  Markwatch:   started (PID $(cat "${MARKWATCH_PID_FILE}")), log -> ${MARKWATCH_LOG_FILE}"
elif [[ "${WATCHER_ENABLED}" == "true" ]]; then
  echo "  Markwatch:   failed to stay running, check log -> ${MARKWATCH_LOG_FILE}"
fi
