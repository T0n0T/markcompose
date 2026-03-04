#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.runtime"
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"
MARKWATCH_PID_FILE="${SCRIPT_DIR}/.markwatch.pid"
MARKWATCH_LOG_FILE="${SCRIPT_DIR}/.markwatch.log"

DEFAULT_MARKFLOW_URL="https://github.com/T0n0T/markflow/releases/latest/download/markflow-dist.tar.gz"
DEFAULT_MARKWATCH_URL="https://github.com/T0n0T/markwatch/releases/latest/download/markwatch-x86_64-unknown-linux-gnu.tar.gz"
DEFAULT_MARKFLOW_ARCHIVE="${SCRIPT_DIR}/markflow-dist.tar.gz"
DEFAULT_MARKWATCH_ARCHIVE="${SCRIPT_DIR}/markwatch-x86_64-unknown-linux-gnu.tar.gz"

usage() {
  cat <<'USAGE'
Usage:
  start.sh [options] <markdown_dir> <watcher_path> [attachments_dir] [host_port]
  start.sh [options] <markdown_dir> <editor_static_dir> <watcher_path> [attachments_dir] [host_port]
  start.sh [options] --use-default-resources <markdown_dir> [attachments_dir] [host_port]

Options:
  --use-default-resources      Use default markflow + markwatch release packages
                               (prefer local tar.gz, auto-download if missing).
  --no-watch                   Do not start markwatch watcher.
  --debounce-ms <num>          markwatch debounce ms (default: 800).
  --reconcile-sec <num>        markwatch reconcile sec (default: 600).
  --watch-log-level <level>    markwatch log level (default: info).
  -h, --help                   Show this message.

Examples:
  ./start.sh /data/blog/md /opt/markwatch/bin/markwatch
  ./start.sh /data/blog/md /data/editor/dist /opt/markwatch/bin/markwatch 8080
  ./start.sh --use-default-resources /data/blog/md
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
  check_num "${port}" "host_port"
  (( port >= 1 && port <= 65535 )) || die "host_port must be in range 1..65535: ${port}"
}

check_docker_compose() {
  docker compose version >/dev/null 2>&1 || die "docker compose is not available"
}

write_env_file() {
  local markdown_dir="$1"
  local editor_dir="$2"
  local attachments_dir="$3"
  local host_port="$4"

  cat >"${ENV_FILE}" <<ENV
MARKDOWN_DIR=${markdown_dir}
EDITOR_STATIC_DIR=${editor_dir}
ATTACHMENTS_DIR=${attachments_dir}
HOST_PORT=${host_port}
COMPOSE_PROJECT_NAME=markcompose
ENV
}

parse_attachments_and_port() {
  local markdown_dir="$1"
  shift
  local -a tail_args=("$@")
  local count="${#tail_args[@]}"

  ATTACHMENTS_DIR="${markdown_dir}/attachments"
  HOST_PORT="8080"

  if (( count == 0 )); then
    return 0
  fi
  if (( count == 1 )); then
    if [[ "${tail_args[0]}" =~ ^[0-9]+$ ]]; then
      HOST_PORT="${tail_args[0]}"
    else
      ATTACHMENTS_DIR="${tail_args[0]}"
    fi
    return 0
  fi
  if (( count == 2 )); then
    ATTACHMENTS_DIR="${tail_args[0]}"
    HOST_PORT="${tail_args[1]}"
    return 0
  fi

  die "Invalid arguments after markdown_dir"
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

resolve_markflow_dist_dir() {
  local extracted_dir="$1"
  local dist_dir="${extracted_dir}/dist"
  local fallback=""

  if [[ -d "${dist_dir}" ]]; then
    echo "${dist_dir}"
    return 0
  fi

  fallback="$(find "${extracted_dir}" -maxdepth 5 -type d -name dist | head -n 1 || true)"
  [[ -n "${fallback}" ]] || die "Cannot find dist directory after extracting markflow archive: ${extracted_dir}"
  echo "${fallback}"
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

try_resolve_markwatch_binary() {
  local input_path="$1"
  local abs_input=""
  local bin_path=""

  if [[ -d "${input_path}" ]]; then
    abs_input="$(to_abs "${input_path}")"
    bin_path="$(resolve_markwatch_binary_from_dir "${abs_input}" || true)"
    [[ -n "${bin_path}" ]] || return 1
    echo "${bin_path}"
    return 0
  fi

  if [[ -f "${input_path}" ]]; then
    abs_input="$(to_abs "${input_path}")"
    chmod +x "${abs_input}"
    echo "${abs_input}"
    return 0
  fi

  return 1
}

resolve_markwatch_binary() {
  local input_path="$1"
  local resolved=""

  resolved="$(try_resolve_markwatch_binary "${input_path}" || true)"
  [[ -n "${resolved}" ]] || die "Watcher path not found: ${input_path}"
  echo "${resolved}"
}

prepare_empty_editor_dir() {
  local empty_dir="${RUNTIME_DIR}/editor-empty"
  rm -rf "${empty_dir}"
  mkdir -p "${empty_dir}"
  echo "${empty_dir}"
}

stop_existing_markwatch() {
  local pid=""
  local i=0

  if [[ ! -f "${MARKWATCH_PID_FILE}" ]]; then
    return 0
  fi

  pid="$(cat "${MARKWATCH_PID_FILE}" 2>/dev/null || true)"
  rm -f "${MARKWATCH_PID_FILE}"

  [[ "${pid}" =~ ^[0-9]+$ ]] || return 0
  if ! kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi

  echo "Stopping existing markwatch process (PID ${pid})"
  kill "${pid}" 2>/dev/null || true
  for (( i = 0; i < 20; i++ )); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  kill -9 "${pid}" 2>/dev/null || true
}

start_markwatch() {
  local markwatch_bin="$1"
  local markdown_dir="$2"
  local debounce_ms="$3"
  local reconcile_sec="$4"
  local watch_log_level="$5"
  local build_cmd=""
  local pid=""

  stop_existing_markwatch
  touch "${MARKWATCH_LOG_FILE}"
  build_cmd="docker compose --env-file \"${ENV_FILE}\" run --rm --no-deps hugo-builder"

  (
    cd "${SCRIPT_DIR}"
    nohup "${markwatch_bin}" \
      --root "${markdown_dir}" \
      --workdir "${SCRIPT_DIR}" \
      --cmd "${build_cmd}" \
      --shell "sh" \
      --debounce-ms "${debounce_ms}" \
      --reconcile-sec "${reconcile_sec}" \
      --log-level "${watch_log_level}" \
      >>"${MARKWATCH_LOG_FILE}" 2>&1 &
    echo $! >"${MARKWATCH_PID_FILE}"
  )

  pid="$(cat "${MARKWATCH_PID_FILE}" 2>/dev/null || true)"
  if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
    echo "WARN: markwatch failed to start; check log: ${MARKWATCH_LOG_FILE}" >&2
    rm -f "${MARKWATCH_PID_FILE}"
    return 1
  fi

  sleep 1
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "WARN: markwatch exited right after startup; check log: ${MARKWATCH_LOG_FILE}" >&2
    rm -f "${MARKWATCH_PID_FILE}"
    return 1
  fi

  return 0
}

USE_DEFAULT_RESOURCES="false"
NO_WATCH="false"
DEBOUNCE_MS="800"
RECONCILE_SEC="600"
WATCH_LOG_LEVEL="info"
MARKFLOW_ARCHIVE="${DEFAULT_MARKFLOW_ARCHIVE}"
MARKWATCH_ARCHIVE="${DEFAULT_MARKWATCH_ARCHIVE}"
POSITIONAL=()

while (( $# > 0 )); do
  case "$1" in
    --use-default-resources)
      USE_DEFAULT_RESOURCES="true"
      shift
      ;;
    --no-watch)
      NO_WATCH="true"
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
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}"

MARKDOWN_DIR=""
EDITOR_STATIC_DIR=""
ATTACHMENTS_DIR=""
HOST_PORT="8080"
START_WATCHER="false"
MARKWATCH_BIN=""
MARKWATCH_STATUS="not-started"
EDITOR_CONFIGURED="false"

if [[ "${USE_DEFAULT_RESOURCES}" == "true" ]]; then
  if (( $# < 1 || $# > 3 )); then
    usage
    die "When using --use-default-resources, expected: <markdown_dir> [attachments_dir] [host_port]"
  fi

  MARKDOWN_DIR="$1"
  parse_attachments_and_port "${MARKDOWN_DIR}" "${@:2}"

  check_num "${DEBOUNCE_MS}" "debounce-ms"
  check_num "${RECONCILE_SEC}" "reconcile-sec"
  require_cmd tar

  MARKFLOW_ARCHIVE="$(resolve_or_download_archive "markflow" "${MARKFLOW_ARCHIVE}" "${DEFAULT_MARKFLOW_URL}")"
  MARKWATCH_ARCHIVE="$(resolve_or_download_archive "markwatch" "${MARKWATCH_ARCHIVE}" "${DEFAULT_MARKWATCH_URL}")"
  MARKFLOW_ARCHIVE="$(to_abs "${MARKFLOW_ARCHIVE}")"
  MARKWATCH_ARCHIVE="$(to_abs "${MARKWATCH_ARCHIVE}")"

  MARKFLOW_EXTRACT_DIR="${RUNTIME_DIR}/markflow"
  MARKWATCH_EXTRACT_DIR="${RUNTIME_DIR}/markwatch"
  extract_tarball "${MARKFLOW_ARCHIVE}" "${MARKFLOW_EXTRACT_DIR}"
  extract_tarball "${MARKWATCH_ARCHIVE}" "${MARKWATCH_EXTRACT_DIR}"

  EDITOR_STATIC_DIR="$(resolve_markflow_dist_dir "${MARKFLOW_EXTRACT_DIR}")"
  MARKWATCH_BIN="$(resolve_markwatch_binary_from_dir "${MARKWATCH_EXTRACT_DIR}" || true)"
  [[ -n "${MARKWATCH_BIN}" ]] || die "Cannot find markwatch binary after extracting default package"
  EDITOR_CONFIGURED="true"
else
  if (( $# < 2 || $# > 5 )); then
    usage
    die "Without --use-default-resources, expected: <markdown_dir> <watcher_path> [attachments_dir] [host_port]"
  fi

  MARKDOWN_DIR="$1"

  WATCHER_CANDIDATE="$(try_resolve_markwatch_binary "$2" || true)"
  if [[ -n "${WATCHER_CANDIDATE}" ]]; then
    MARKWATCH_BIN="${WATCHER_CANDIDATE}"
    EDITOR_STATIC_DIR="$(prepare_empty_editor_dir)"
    EDITOR_CONFIGURED="false"
    parse_attachments_and_port "${MARKDOWN_DIR}" "${@:3}"
  else
    if (( $# < 3 )); then
      usage
      die "Without --use-default-resources, watcher_path is required"
    fi
    EDITOR_STATIC_DIR="$2"
    MARKWATCH_BIN="$(resolve_markwatch_binary "$3")"
    EDITOR_CONFIGURED="true"
    parse_attachments_and_port "${MARKDOWN_DIR}" "${@:4}"
  fi
fi

if [[ "${NO_WATCH}" != "true" ]]; then
  START_WATCHER="true"
fi

check_num "${DEBOUNCE_MS}" "debounce-ms"
check_num "${RECONCILE_SEC}" "reconcile-sec"
check_port "${HOST_PORT}"
check_docker_compose
ensure_dir "${MARKDOWN_DIR}"
ensure_dir_or_create "${ATTACHMENTS_DIR}"
ensure_dir_or_create "${EDITOR_STATIC_DIR}"

MARKDOWN_DIR="$(to_abs "${MARKDOWN_DIR}")"
EDITOR_STATIC_DIR="$(to_abs "${EDITOR_STATIC_DIR}")"
ATTACHMENTS_DIR="$(to_abs "${ATTACHMENTS_DIR}")"
MARKWATCH_BIN="$(to_abs "${MARKWATCH_BIN}")"

[[ -x "${MARKWATCH_BIN}" ]] || die "Watcher binary not executable: ${MARKWATCH_BIN}"

check_no_spaces "${MARKDOWN_DIR}"
check_no_spaces "${EDITOR_STATIC_DIR}"
check_no_spaces "${ATTACHMENTS_DIR}"
check_no_spaces "${MARKWATCH_BIN}"

write_env_file "${MARKDOWN_DIR}" "${EDITOR_STATIC_DIR}" "${ATTACHMENTS_DIR}" "${HOST_PORT}"

echo "Configuration written to ${ENV_FILE}"
echo "  MARKDOWN_DIR=${MARKDOWN_DIR}"
echo "  EDITOR_STATIC_DIR=${EDITOR_STATIC_DIR}"
echo "  ATTACHMENTS_DIR=${ATTACHMENTS_DIR}"
echo "  HOST_PORT=${HOST_PORT}"

"${SCRIPT_DIR}/build.sh" "${ENV_FILE}"

(
  cd "${SCRIPT_DIR}"
  docker compose --env-file "${ENV_FILE}" up -d nginx
)

if [[ "${START_WATCHER}" == "true" ]]; then
  if start_markwatch "${MARKWATCH_BIN}" "${MARKDOWN_DIR}" "${DEBOUNCE_MS}" "${RECONCILE_SEC}" "${WATCH_LOG_LEVEL}"; then
    MARKWATCH_STATUS="started"
  else
    MARKWATCH_STATUS="failed"
  fi
fi

echo "Service started:"
echo "  Blog:        http://127.0.0.1:${HOST_PORT}/"
if [[ "${EDITOR_CONFIGURED}" == "true" ]]; then
  echo "  Editor:      http://127.0.0.1:${HOST_PORT}/editor/"
else
  echo "  Editor:      not configured (empty dir mounted on /editor/)"
fi
echo "  Attachments: http://127.0.0.1:${HOST_PORT}/attachments/"
if [[ "${MARKWATCH_STATUS}" == "started" ]]; then
  echo "  Markwatch:   started (PID $(cat "${MARKWATCH_PID_FILE}")), log -> ${MARKWATCH_LOG_FILE}"
elif [[ "${START_WATCHER}" == "true" ]]; then
  echo "  Markwatch:   failed to stay running, check log -> ${MARKWATCH_LOG_FILE}"
fi
