#!/usr/bin/env bash

mc::waline::sqlite_exists_in_volume() {
  local env_file="$1"
  local check_cmd=''

  check_cmd=$(cat <<'EOF'
set -eu
 db_dir="${SQLITE_PATH:-/app/data}"
 db_name="${SQLITE_DB:-waline}"
 db_path="${db_dir%/}/${db_name}.sqlite"
 [ -s "${db_path}" ]
EOF
)

  (
    cd "${MARKCOMPOSE_REPO_ROOT}" || return 1
    docker compose --env-file "${env_file}" run --rm --no-deps --entrypoint sh waline -lc "${check_cmd}" >/dev/null 2>&1
  )
}

mc::waline::seed_volume_if_needed() {
  local env_file="$1"
  local seed_path="$2"
  local seed_cmd=''

  if mc::waline::sqlite_exists_in_volume "${env_file}"; then
    mc::info "Waline SQLite already exists in volume; keeping existing users/comments."
    return 0
  fi

  [[ -f "${seed_path}" ]] || mc::die "Waline SQLite seed file not found: ${seed_path}"

  mc::step "Waline SQLite DB missing; initializing volume from seed"
  seed_cmd=$(cat <<'EOF'
set -eu
 db_dir="${SQLITE_PATH:-/app/data}"
 db_name="${SQLITE_DB:-waline}"
 db_path="${db_dir%/}/${db_name}.sqlite"
 mkdir -p "${db_dir}"
 cat > "${db_path}"
EOF
)

  (
    cd "${MARKCOMPOSE_REPO_ROOT}" || return 1
    docker compose --env-file "${env_file}" run --rm --no-deps --entrypoint sh waline -lc "${seed_cmd}" < "${seed_path}"
  )

  mc::waline::sqlite_exists_in_volume "${env_file}" || mc::die "Waline SQLite seed import completed but database file is still missing"
  mc::success "Waline SQLite seed import completed."
}
