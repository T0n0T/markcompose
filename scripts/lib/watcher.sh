#!/usr/bin/env bash

mc::watcher::stop_existing() {
  local pid_file="$1"
  local existing_pid=""
  local wait_attempt=0

  [[ -f "${pid_file}" ]] || return 0

  existing_pid="$(cat "${pid_file}" 2>/dev/null || true)"
  rm -f "${pid_file}"

  [[ "${existing_pid}" =~ ^[0-9]+$ ]] || return 0
  if ! kill -0 "${existing_pid}" 2>/dev/null; then
    return 0
  fi

  mc::step "Stopping existing markwatch process"
  mc::kv "PID" "${existing_pid}"
  kill "${existing_pid}" 2>/dev/null || true
  for (( wait_attempt = 0; wait_attempt < 20; wait_attempt++ )); do
    if ! kill -0 "${existing_pid}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  kill -9 "${existing_pid}" 2>/dev/null || true
}

mc::watcher::start() {
  local watcher_command="$1"
  local markdown_dir="$2"
  local entrypoint="$3"
  local env_file="$4"
  local default_watcher_enabled="$5"
  local debounce_ms="$6"
  local reconcile_sec="$7"
  local watch_log_level="$8"
  local workdir="$9"
  local pid_file="${10}"
  local log_file="${11}"
  local build_command=""
  local run_command=""
  local watcher_pid=""

  mc::watcher::stop_existing "${pid_file}"
  touch "${log_file}"
  build_command="$(printf '%q' "${entrypoint}") build $(printf '%q' "${env_file}")"

  run_command="${watcher_command} --root $(printf '%q' "${markdown_dir}") --workdir $(printf '%q' "${workdir}") --cmd $(printf '%q' "${build_command}") --shell sh"
  if [[ "${default_watcher_enabled}" == "true" ]]; then
    run_command="${run_command} --debounce-ms $(printf '%q' "${debounce_ms}") --reconcile-sec $(printf '%q' "${reconcile_sec}") --log-level $(printf '%q' "${watch_log_level}")"
  fi

  (
    cd "${workdir}" || return 1
    nohup bash -lc "${run_command}" >>"${log_file}" 2>&1 &
    echo $! >"${pid_file}"
  )

  watcher_pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ -z "${watcher_pid}" ]] || ! kill -0 "${watcher_pid}" 2>/dev/null; then
    mc::warn "markwatch failed to start; check log: ${log_file}"
    rm -f "${pid_file}"
    return 1
  fi

  sleep 1
  if ! kill -0 "${watcher_pid}" 2>/dev/null; then
    mc::warn "markwatch exited right after startup; check log: ${log_file}"
    rm -f "${pid_file}"
    return 1
  fi

  return 0
}
