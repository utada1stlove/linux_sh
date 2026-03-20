#!/usr/bin/env bash

set -Eeuo pipefail

LINUX_SH_REPO_OWNER="${LINUX_SH_REPO_OWNER:-utada1stlove}"
LINUX_SH_REPO_NAME="${LINUX_SH_REPO_NAME:-linux_sh}"
LINUX_SH_REF="${LINUX_SH_REF:-main}"
LINUX_SH_ARCHIVE_URL="${LINUX_SH_ARCHIVE_URL:-https://codeload.github.com/${LINUX_SH_REPO_OWNER}/${LINUX_SH_REPO_NAME}/tar.gz/refs/heads/${LINUX_SH_REF}}"
LINUX_SH_FILE_BASE_URL="${LINUX_SH_FILE_BASE_URL:-}"

log() {
  printf '[install] %s\n' "$*"
}

die() {
  printf '[install] ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

need_command() {
  command_exists "$1" || die "Missing required command: $1"
}

download_to() {
  local url="$1"
  local output="$2"

  if command_exists wget; then
    wget -qO "${output}" "${url}"
    return 0
  fi

  if command_exists curl; then
    curl -fsSL "${url}" -o "${output}"
    return 0
  fi

  die "Either wget or curl is required."
}

download_repo_archive() {
  local url="$1"
  local output="$2"
  download_to "${url}" "${output}"
}

download_repo_files() {
  local target_dir="$1"
  local rel_path
  local target_path
  local file_url
  local files=(
    bootstrap.sh
    lib/common.sh
    stages/00-preflight.sh
    stages/10-packages.sh
    stages/20-timezone.sh
    stages/30-vnstat.sh
    stages/40-shell.sh
    stages/50-bbr.sh
    stages/60-youtube.sh
  )

  [[ -n "${LINUX_SH_FILE_BASE_URL}" ]] || die "LINUX_SH_FILE_BASE_URL is required for file-download mode."

  for rel_path in "${files[@]}"; do
    target_path="${target_dir}/${rel_path}"
    file_url="${LINUX_SH_FILE_BASE_URL}/${rel_path}"
    mkdir -p "$(dirname "${target_path}")"
    log "Downloading ${rel_path}"
    download_to "${file_url}" "${target_path}"
  done
}

main() {
  local work_dir archive_path extracted_dir

  [[ "${EUID}" -eq 0 ]] || die "Run as root. Example: wget -qO- https://raw.githubusercontent.com/${LINUX_SH_REPO_OWNER}/${LINUX_SH_REPO_NAME}/${LINUX_SH_REF}/install.sh | sudo bash"

  need_command bash
  need_command mktemp

  work_dir="$(mktemp -d)"
  trap 'rm -rf "${work_dir}"' EXIT

  if [[ -n "${LINUX_SH_FILE_BASE_URL}" ]]; then
    extracted_dir="${work_dir}/${LINUX_SH_REPO_NAME}-${LINUX_SH_REF}"
    mkdir -p "${extracted_dir}"
    log "Downloading ${LINUX_SH_REPO_NAME}@${LINUX_SH_REF} from file mirror"
    download_repo_files "${extracted_dir}"
  else
    need_command tar
    need_command find

    archive_path="${work_dir}/${LINUX_SH_REPO_NAME}.tar.gz"

    log "Downloading ${LINUX_SH_REPO_NAME}@${LINUX_SH_REF}"
    download_repo_archive "${LINUX_SH_ARCHIVE_URL}" "${archive_path}"

    log "Extracting archive"
    tar -xzf "${archive_path}" -C "${work_dir}"

    extracted_dir="$(find "${work_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  fi

  [[ -n "${extracted_dir}" ]] || die "Failed to locate extracted project directory."
  [[ -f "${extracted_dir}/bootstrap.sh" ]] || die "bootstrap.sh was not found in the downloaded archive."

  chmod 0755 "${extracted_dir}/bootstrap.sh"

  log "Starting bootstrap"
  exec "${extracted_dir}/bootstrap.sh" "$@"
}

main "$@"
