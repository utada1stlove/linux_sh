#!/usr/bin/env bash

LINUX_SH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_SH_ROOT_DIR="$(cd "${LINUX_SH_LIB_DIR}/.." && pwd)"
LINUX_SH_STAGE_DIR="${LINUX_SH_ROOT_DIR}/stages"

declare -ag STAGE_IDS=()
declare -ag STAGE_DESCRIPTIONS=()
declare -ag STAGE_CHECK_FUNCS=()
declare -ag STAGE_APPLY_FUNCS=()

quote_command() {
  local arg
  local quoted=()
  for arg in "$@"; do
    quoted+=("$(printf '%q' "${arg}")")
  done
  printf '%s ' "${quoted[@]}"
}

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "${level}" "$*"
}

info() {
  log INFO "$@"
}

warn() {
  log WARN "$@" >&2
}

error() {
  log ERROR "$@" >&2
}

die() {
  error "$@"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

register_stage() {
  local stage_id="$1"
  local description="$2"
  local check_fn="$3"
  local apply_fn="$4"

  STAGE_IDS+=("${stage_id}")
  STAGE_DESCRIPTIONS+=("${description}")
  STAGE_CHECK_FUNCS+=("${check_fn}")
  STAGE_APPLY_FUNCS+=("${apply_fn}")
}

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '[DRY-RUN] %s\n' "$(quote_command "$@")"
    return 0
  fi

  "$@"
}

ensure_directory() {
  run mkdir -p "$1"
}

write_text_file() {
  local path="$1"
  local content="$2"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "Would write ${path}"
    return 0
  fi

  printf '%s' "${content}" >"${path}"
}

make_executable() {
  run chmod 0755 "$1"
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local suffix='[y/N]'
  local answer

  if [[ "${default}" =~ ^[Yy]$ ]]; then
    suffix='[Y/n]'
  fi

  if [[ "${AUTO_YES:-0}" == "1" ]]; then
    return 0
  fi

  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    [[ "${default}" =~ ^[Yy]$ ]]
    return
  fi

  while true; do
    printf '%s %s ' "${prompt}" "${suffix}" >/dev/tty
    IFS= read -r answer </dev/tty || return 1
    answer="${answer:-${default}}"
    case "${answer}" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO)
        return 1
        ;;
    esac
  done
}

current_timezone() {
  local target

  if [[ -f /etc/timezone ]]; then
    tr -d '\n' </etc/timezone
    return 0
  fi

  if [[ -L /etc/localtime ]]; then
    target="$(readlink /etc/localtime || true)"
    if [[ "${target}" == *"/zoneinfo/"* ]]; then
      printf '%s\n' "${target##*/zoneinfo/}"
      return 0
    fi
  fi

  printf 'UTC\n'
}

default_interface() {
  local iface=""
  iface="$(ip -o route show default 2>/dev/null | awk 'NR == 1 { print $5 }' || true)"
  printf '%s\n' "${iface}"
}

virtualization_type() {
  if command_exists systemd-detect-virt; then
    systemd-detect-virt 2>/dev/null || true
  fi
}

is_lxc_container() {
  case "$(virtualization_type)" in
    lxc|lxc-libvirt)
      return 0
      ;;
  esac

  return 1
}
