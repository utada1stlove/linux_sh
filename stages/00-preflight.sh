#!/usr/bin/env bash

stage_check_preflight() {
  local rc=0
  local virtualization="none"
  local os_name="unknown"
  local os_flags=""

  if [[ "${EUID}" -ne 0 ]]; then
    warn "This bootstrap must run as root."
    rc=1
  else
    info "Privilege check: running as root."
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_name="${PRETTY_NAME:-${ID:-unknown}}"
    os_flags="${ID:-} ${ID_LIKE:-}"
    info "Detected OS: ${os_name}"
    if [[ "${os_flags}" != *debian* ]]; then
      warn "This script targets Debian-family systems."
      rc=1
    fi
  else
    warn "/etc/os-release is missing."
    rc=1
  fi

  if command_exists systemd-detect-virt; then
    virtualization="$(systemd-detect-virt 2>/dev/null || true)"
  fi
  info "Virtualization: ${virtualization:-none}"

  command_exists apt-get || {
    warn "apt-get is required."
    rc=1
  }

  command_exists dpkg || {
    warn "dpkg is required."
    rc=1
  }

  if ! command_exists systemctl; then
    warn "systemctl is missing; service persistence may be unavailable."
  fi

  return "${rc}"
}

stage_apply_preflight() {
  if stage_check_preflight; then
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    warn "Preflight would fail on this host, but dry-run will continue."
    return 0
  fi

  die "Preflight checks failed. Fix the environment and rerun."
}

register_stage "preflight" "Validate the Debian host and required tooling." "stage_check_preflight" "stage_apply_preflight"
