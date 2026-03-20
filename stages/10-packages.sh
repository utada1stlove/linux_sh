#!/usr/bin/env bash

desired_packages() {
  local packages=(
    sudo
    curl
    wget
    vim
    lsof
    ca-certificates
    iproute2
    iptables
    vnstat
  )

  if command_exists apt-cache && apt-cache show vnstati >/dev/null 2>&1; then
    packages+=(vnstati)
  fi

  printf '%s\n' "${packages[@]}"
}

stage_check_packages() {
  local pkg
  local missing=()

  if ! command_exists dpkg; then
    warn "dpkg is unavailable; package state cannot be inspected."
    return 1
  fi

  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
      missing+=("${pkg}")
    fi
  done < <(desired_packages)

  if ((${#missing[@]} == 0)); then
    info "Base packages are installed."
    return 0
  fi

  warn "Missing packages: ${missing[*]}"
  return 1
}

stage_apply_packages() {
  local packages=()
  local pkg

  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] && packages+=("${pkg}")
  done < <(desired_packages)

  run apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

register_stage "packages" "Install the Debian base packages used by later stages." "stage_check_packages" "stage_apply_packages"
