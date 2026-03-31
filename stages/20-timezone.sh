#!/usr/bin/env bash

timezone_exists() {
  [[ -e "/usr/share/zoneinfo/$1" ]]
}

ensure_timezone_selection() {
  local current choice custom_value
  current="$(current_timezone)"

  if [[ -n "${SELECTED_TIMEZONE:-}" ]]; then
    timezone_exists "${SELECTED_TIMEZONE}" || die "Unknown timezone: ${SELECTED_TIMEZONE}"
    return 0
  fi

  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    SELECTED_TIMEZONE="${current}"
    return 0
  fi

  while true; do
    cat >/dev/tty <<EOF
Select a timezone:
  1) Keep current (${current})
  2) Asia/Singapore
  3) Asia/Shanghai
  4) UTC
  5) America/Los_Angeles
  6) America/New_York
  7) Europe/London
  8) Custom value
EOF
    printf 'Choice [1-8]: ' >/dev/tty
    IFS= read -r choice </dev/tty || die "Unable to read timezone choice."

    case "${choice:-1}" in
      1)
        SELECTED_TIMEZONE="${current}"
        ;;
      2)
        SELECTED_TIMEZONE="Asia/Singapore"
        ;;
      3)
        SELECTED_TIMEZONE="Asia/Shanghai"
        ;;
      4)
        SELECTED_TIMEZONE="UTC"
        ;;
      5)
        SELECTED_TIMEZONE="America/Los_Angeles"
        ;;
      6)
        SELECTED_TIMEZONE="America/New_York"
        ;;
      7)
        SELECTED_TIMEZONE="Europe/London"
        ;;
      8)
        printf 'Enter timezone (for example Asia/Tokyo): ' >/dev/tty
        IFS= read -r custom_value </dev/tty || die "Unable to read custom timezone."
        SELECTED_TIMEZONE="${custom_value}"
        ;;
      *)
        warn "Please choose a value between 1 and 8."
        continue
        ;;
    esac

    timezone_exists "${SELECTED_TIMEZONE}" && break
    warn "Timezone not found: ${SELECTED_TIMEZONE}"
    SELECTED_TIMEZONE=""
  done
}

ntp_is_enabled() {
  if command_exists timedatectl && timedatectl show -p NTP --value >/dev/null 2>&1; then
    [[ "$(timedatectl show -p NTP --value 2>/dev/null || true)" == "yes" ]]
    return
  fi

  if command_exists systemctl; then
    systemctl is-enabled --quiet systemd-timesyncd.service >/dev/null 2>&1
    return
  fi

  return 1
}

clock_is_synchronized() {
  if command_exists timedatectl && timedatectl show -p NTPSynchronized --value >/dev/null 2>&1; then
    [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]
    return
  fi

  if command_exists timedatectl && timedatectl show -p SystemClockSynchronized --value >/dev/null 2>&1; then
    [[ "$(timedatectl show -p SystemClockSynchronized --value 2>/dev/null || true)" == "yes" ]]
    return
  fi

  return 1
}

timedatectl_available() {
  command_exists timedatectl &&
    timedatectl show -p Timezone --value >/dev/null 2>&1
}

stage_check_timezone() {
  local current
  local rc=0

  current="$(current_timezone)"
  info "Current timezone: ${current}"

  if ((INSPECT_ONLY == 1)) && [[ -z "${SELECTED_TIMEZONE:-}" ]]; then
    ntp_is_enabled && info "NTP: enabled." || warn "NTP: not confirmed."
    clock_is_synchronized && info "Clock sync: confirmed." || warn "Clock sync: not confirmed."
    return 0
  fi

  ensure_timezone_selection
  info "Target timezone: ${SELECTED_TIMEZONE}"

  if [[ "${current}" != "${SELECTED_TIMEZONE}" ]]; then
    warn "Timezone differs from the selected target."
    rc=1
  fi

  if ! ntp_is_enabled; then
    warn "NTP is not enabled."
    rc=1
  fi

  if ! clock_is_synchronized; then
    warn "The system clock is not synchronized yet."
    rc=1
  fi

  return "${rc}"
}

stage_apply_timezone() {
  ensure_timezone_selection

  if timedatectl_available; then
    run timedatectl set-timezone "${SELECTED_TIMEZONE}"
  else
    run ln -snf "/usr/share/zoneinfo/${SELECTED_TIMEZONE}" /etc/localtime
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      info "Would write /etc/timezone"
    else
      printf '%s\n' "${SELECTED_TIMEZONE}" >/etc/timezone
    fi
  fi

  if timedatectl_available; then
    run timedatectl set-ntp true || true
  fi

  if command_exists systemctl && systemctl list-unit-files systemd-timesyncd.service >/dev/null 2>&1; then
    run systemctl enable --now systemd-timesyncd.service || true
    run systemctl restart systemd-timesyncd.service || true
  fi
}

register_stage "timezone" "Select the timezone and enable time synchronization." "stage_check_timezone" "stage_apply_timezone"
