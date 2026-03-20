#!/usr/bin/env bash

QUIC_SERVICE_NAME="linux-sh-disable-quic.service"
QUIC_HELPER_PATH="/usr/local/lib/linux_sh/block-quic.sh"
QUIC_SERVICE_PATH="/etc/systemd/system/${QUIC_SERVICE_NAME}"

ensure_quic_block_mode() {
  if [[ "${ENABLE_QUIC_BLOCK:-}" == "enabled" || "${ENABLE_QUIC_BLOCK:-}" == "disabled" ]]; then
    return 0
  fi

  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    ENABLE_QUIC_BLOCK="disabled"
    return 0
  fi

  if confirm "Block outbound UDP/443 to suppress QUIC system-wide?" "Y"; then
    ENABLE_QUIC_BLOCK="enabled"
  else
    ENABLE_QUIC_BLOCK="disabled"
  fi
}

quic_rule_present() {
  command_exists iptables &&
    iptables -w -C OUTPUT -p udp --dport 443 -j REJECT >/dev/null 2>&1
}

quic_service_ready() {
  command_exists systemctl &&
    systemctl is-enabled --quiet "${QUIC_SERVICE_NAME}" >/dev/null 2>&1 &&
    systemctl is-active --quiet "${QUIC_SERVICE_NAME}" >/dev/null 2>&1
}

stage_check_youtube_quic() {
  if ((INSPECT_ONLY == 1)) && [[ -z "${ENABLE_QUIC_BLOCK:-}" ]]; then
    if quic_service_ready || quic_rule_present; then
      info "QUIC suppression is currently enabled."
    else
      info "QUIC suppression is currently disabled."
    fi
    return 0
  fi

  ensure_quic_block_mode
  if [[ "${ENABLE_QUIC_BLOCK}" == "disabled" ]]; then
    if quic_service_ready || quic_rule_present; then
      warn "QUIC suppression is enabled but the selected target is disabled."
      return 1
    fi
    info "QUIC suppression is disabled by choice."
    return 0
  fi

  if [[ -x "${QUIC_HELPER_PATH}" ]] && quic_rule_present; then
    if command_exists systemctl; then
      quic_service_ready && info "QUIC suppression is enabled." && return 0
      warn "QUIC rule exists but ${QUIC_SERVICE_NAME} is not active."
      return 1
    fi
    info "QUIC suppression rule is present."
    return 0
  fi

  warn "QUIC suppression is not fully configured."
  return 1
}

stage_apply_youtube_quic() {
  local helper_script service_unit

  ensure_quic_block_mode
  if [[ "${ENABLE_QUIC_BLOCK}" == "disabled" ]]; then
    if [[ -x "${QUIC_HELPER_PATH}" ]]; then
      run "${QUIC_HELPER_PATH}" remove || true
    fi
    if command_exists systemctl && [[ -f "${QUIC_SERVICE_PATH}" ]]; then
      run systemctl disable --now "${QUIC_SERVICE_NAME}" || true
      run systemctl daemon-reload || true
    fi
    return 0
  fi

  ensure_directory /usr/local/lib/linux_sh

  helper_script='#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:-add}"

if ! command -v iptables >/dev/null 2>&1; then
  echo "iptables is required for QUIC suppression." >&2
  exit 1
fi

case "${action}" in
  add)
    if ! iptables -w -C OUTPUT -p udp --dport 443 -j REJECT >/dev/null 2>&1; then
      iptables -w -A OUTPUT -p udp --dport 443 -j REJECT
    fi
    ;;
  remove)
    while iptables -w -C OUTPUT -p udp --dport 443 -j REJECT >/dev/null 2>&1; do
      iptables -w -D OUTPUT -p udp --dport 443 -j REJECT
    done
    ;;
  *)
    echo "Usage: $0 {add|remove}" >&2
    exit 1
    ;;
esac
'
  write_text_file "${QUIC_HELPER_PATH}" "${helper_script}"
  make_executable "${QUIC_HELPER_PATH}"

  if command_exists systemctl; then
    service_unit='[Unit]
Description=Disable outbound QUIC for linux_sh
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/linux_sh/block-quic.sh add
ExecStop=/usr/local/lib/linux_sh/block-quic.sh remove
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
'
    write_text_file "${QUIC_SERVICE_PATH}" "${service_unit}"
    run systemctl daemon-reload
    run systemctl enable --now "${QUIC_SERVICE_NAME}"
  else
    run "${QUIC_HELPER_PATH}" add
  fi
}

register_stage "youtube-quic" "Optionally block outbound UDP/443 to disable QUIC." "stage_check_youtube_quic" "stage_apply_youtube_quic"
