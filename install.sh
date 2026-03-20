#!/usr/bin/env bash

set -Eeuo pipefail

LINUX_SH_REPO_OWNER="${LINUX_SH_REPO_OWNER:-utada1stlove}"
LINUX_SH_REPO_NAME="${LINUX_SH_REPO_NAME:-linux_sh}"
LINUX_SH_REF="${LINUX_SH_REF:-main}"
LINUX_SH_ARCHIVE_URL="${LINUX_SH_ARCHIVE_URL:-https://codeload.github.com/${LINUX_SH_REPO_OWNER}/${LINUX_SH_REPO_NAME}/tar.gz/refs/heads/${LINUX_SH_REF}}"

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

download_archive() {
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

main() {
  local work_dir archive_path extracted_dir

  [[ "${EUID}" -eq 0 ]] || die "Run as root. Example: sudo bash <(wget -qO- https://raw.githubusercontent.com/${LINUX_SH_REPO_OWNER}/${LINUX_SH_REPO_NAME}/${LINUX_SH_REF}/install.sh)"

  need_command bash
  need_command tar
  need_command mktemp
  need_command find

  work_dir="$(mktemp -d)"
  archive_path="${work_dir}/${LINUX_SH_REPO_NAME}.tar.gz"
  trap 'rm -rf "${work_dir}"' EXIT

  log "Downloading ${LINUX_SH_REPO_NAME}@${LINUX_SH_REF}"
  download_archive "${LINUX_SH_ARCHIVE_URL}" "${archive_path}"

  log "Extracting archive"
  tar -xzf "${archive_path}" -C "${work_dir}"

  extracted_dir="$(find "${work_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "${extracted_dir}" ]] || die "Failed to locate extracted project directory."
  [[ -f "${extracted_dir}/bootstrap.sh" ]] || die "bootstrap.sh was not found in the downloaded archive."

  chmod 0755 "${extracted_dir}/bootstrap.sh"

  log "Starting bootstrap"
  exec "${extracted_dir}/bootstrap.sh" "$@"
}

main "$@"
