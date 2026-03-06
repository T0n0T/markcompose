#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly MC_BUILD_HUGO_SITE_DIR="${MARKCOMPOSE_REPO_ROOT}/hugo-site"
readonly MC_BUILD_REUSABLE_LAYOUTS_DIR="${MARKCOMPOSE_REPO_ROOT}/hugo-reuse/layouts"
readonly MC_BUILD_HUGO_IMAGE="docker.io/hugomods/hugo:dart-sass-non-root"
readonly MC_BUILD_DEFAULT_ADAPTER_OUTPUT_DIR="${MARKCOMPOSE_RUNTIME_DIR}/content-adapted"

mc::build::ensure_reusable_layouts() {
  [[ -d "${MC_BUILD_REUSABLE_LAYOUTS_DIR}" ]] || mc::die "Reusable layouts directory not found: ${MC_BUILD_REUSABLE_LAYOUTS_DIR}"
  [[ -f "${MC_BUILD_REUSABLE_LAYOUTS_DIR}/_markup/render-image.html" ]] || mc::die "Reusable template not found: ${MC_BUILD_REUSABLE_LAYOUTS_DIR}/_markup/render-image.html"
  [[ -f "${MC_BUILD_REUSABLE_LAYOUTS_DIR}/_markup/render-link.html" ]] || mc::die "Reusable template not found: ${MC_BUILD_REUSABLE_LAYOUTS_DIR}/_markup/render-link.html"
}

mc::build::install_reusable_layouts() {
  local src=""
  local rel=""
  local dest=""

  mc::build::ensure_reusable_layouts
  mkdir -p "${MC_BUILD_HUGO_SITE_DIR}/layouts"

  while IFS= read -r -d '' src; do
    rel="${src#"${MC_BUILD_REUSABLE_LAYOUTS_DIR}"/}"
    dest="${MC_BUILD_HUGO_SITE_DIR}/layouts/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp "${src}" "${dest}"
  done < <(find "${MC_BUILD_REUSABLE_LAYOUTS_DIR}" -type f -print0)
}

mc::build::run_hugo_new_site() {
  local target_dir_name="${1:-hugo-site}"

  mc::build::ensure_reusable_layouts
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "${MARKCOMPOSE_REPO_ROOT}:/work" \
    -w /work \
    "${MC_BUILD_HUGO_IMAGE}" \
    sh -lc "hugo new site ${target_dir_name}"
}

mc::build::init_hugo_site() {
  if [[ -e "${MC_BUILD_HUGO_SITE_DIR}" ]]; then
    mc::die "hugo-site already exists: ${MC_BUILD_HUGO_SITE_DIR}"
  fi

  mc::step "Initializing hugo-site with Hugo image"
  mc::build::run_hugo_new_site "hugo-site"
  mc::build::install_reusable_layouts
  mc::success "Initialized hugo-site and installed reusable layouts."
}

mc::build::init_hugo_site_if_missing() {
  if [[ -d "${MC_BUILD_HUGO_SITE_DIR}" ]]; then
    return 0
  fi

  mc::step "hugo-site not found. Bootstrapping a fresh Hugo site"
  mc::build::run_hugo_new_site "hugo-site"
  mc::build::install_reusable_layouts
  mc::success "Initialized hugo-site and installed reusable layouts."
}

mc::build::gate_check_output() {
  local generated_site_dir="$1"
  [[ -f "${generated_site_dir}/index.html" ]] || mc::die "Gate failed: generated site does not contain index.html"
}

mc::build::resolve_adapter_script_path() {
  local script_path="$1"
  if [[ "${script_path}" == /* ]]; then
    printf '%s\n' "${script_path}"
    return 0
  fi
  printf '%s\n' "${MARKCOMPOSE_REPO_ROOT}/${script_path}"
}

mc::build::prepare_adapted_content_dir() {
  local input_dir="$1"
  local adapted_output_dir="$2"
  local adapter_script="$3"

  [[ -x "${adapter_script}" ]] || mc::die "Adapter script not found or not executable: ${adapter_script}"

  rm -rf "${adapted_output_dir}" 2>/dev/null || true
  mkdir -p "$(dirname "${adapted_output_dir}")"

  mc::step "Preparing adapted content"
  mc::kv "Input" "${input_dir}"
  mc::kv "Output" "${adapted_output_dir}"
  "${adapter_script}" "${input_dir}" "${adapted_output_dir}"
}

mc::build::run_hugo_build_to_staging() {
  local env_file="$1"
  local staging_dir="$2"
  local owner_uid_gid="$3"
  local container_content_dir="$4"
  local hugo_base_url="$5"
  shift 5
  local build_cmd=""

  build_cmd="$(cat <<EOF
set -eu
hugo \\
  --source /site \\
  --contentDir ${container_content_dir} \\
  --destination /out \\
  --baseURL "${hugo_base_url}" \
  --cleanDestinationDir \\
  --noBuildLock

if [ -n "\${HUGO_ASSETS_DIR:-}" ] && [ -d "/markdown/\${HUGO_ASSETS_DIR}" ]; then
  mkdir -p "/out/\${HUGO_ASSETS_DIR}"
  cp -a "/markdown/\${HUGO_ASSETS_DIR}/." "/out/\${HUGO_ASSETS_DIR}/"
fi

chown -R ${owner_uid_gid} /out
EOF
)"

  (
    cd "${MARKCOMPOSE_REPO_ROOT}" || return 1
    docker compose --env-file "${env_file}" run --rm --no-deps \
      -v "${staging_dir}:/out" \
      "$@" \
      hugo-builder \
      sh -lc "${build_cmd}"
  )
}

mc::build::publish_staging_to_public() {
  local env_file="$1"
  local staging_dir="$2"
  local publish_cmd='set -eu
find /public -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -R /staging/. /public/
chmod 755 /public
find /public -type d -exec chmod 755 {} +
find /public -type f -exec chmod 644 {} +'

  (
    cd "${MARKCOMPOSE_REPO_ROOT}" || return 1
    docker compose --env-file "${env_file}" run --rm --no-deps \
      --user 0:0 \
      -v "${staging_dir}:/staging:ro" \
      hugo-builder \
      sh -lc "${publish_cmd}"
  )
}
