#!/usr/bin/env bash

bbr_virtualization() {
  virtualization_type
}

bbr_is_lxc() {
  case "$(bbr_virtualization)" in
    lxc|lxc-libvirt)
      return 0
      ;;
  esac

  return 1
}

bbr_possible() {
  if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    return 0
  fi

  command_exists modprobe && modprobe -n tcp_bbr >/dev/null 2>&1
}

bbr_runtime_available() {
  [[ -r /proc/sys/net/core/default_qdisc ]] &&
    [[ -r /proc/sys/net/ipv4/tcp_congestion_control ]] &&
    [[ -r /proc/sys/net/ipv4/tcp_mtu_probing ]] &&
    [[ -r /proc/sys/net/ipv4/tcp_slow_start_after_idle ]] &&
    [[ -r /proc/sys/net/ipv4/tcp_fastopen ]]
}

stage_check_bbr() {
  local current_qdisc current_cc current_mtu_probing current_slow_start_after_idle current_fastopen

  if bbr_is_lxc; then
    info "LXC detected; BBR stage will be skipped."
    return 0
  fi

  if ! bbr_possible; then
    warn "The current kernel does not expose BBR support."
    return 0
  fi

  if ! bbr_runtime_available; then
    warn "The current environment does not expose the required BBR sysctl paths."
    return 0
  fi

  current_qdisc="$(< /proc/sys/net/core/default_qdisc)"
  current_cc="$(< /proc/sys/net/ipv4/tcp_congestion_control)"
  current_mtu_probing="$(< /proc/sys/net/ipv4/tcp_mtu_probing)"
  current_slow_start_after_idle="$(< /proc/sys/net/ipv4/tcp_slow_start_after_idle)"
  current_fastopen="$(< /proc/sys/net/ipv4/tcp_fastopen)"

  if [[ "${current_qdisc}" == "fq" ]] &&
    [[ "${current_cc}" == "bbr" ]] &&
    [[ "${current_mtu_probing}" == "1" ]] &&
    [[ "${current_slow_start_after_idle}" == "0" ]] &&
    [[ "${current_fastopen}" == "0" ]] &&
    [[ -f /etc/sysctl.d/99-linux-sh-bbr.conf ]]; then
    info "BBR and TCP stability tuning are configured."
    return 0
  fi

  warn "BBR or TCP stability tuning is not fully configured."
  return 1
}

stage_apply_bbr() {
  local bbr_conf

  if bbr_is_lxc; then
    info "Skipping BBR because the host is LXC."
    return 0
  fi

  if ! bbr_possible; then
    warn "Skipping BBR because the current kernel does not support it."
    return 0
  fi

  if ! bbr_runtime_available; then
    warn "Skipping BBR because the current environment does not expose the required sysctl paths."
    return 0
  fi

  if command_exists modprobe; then
    run modprobe tcp_bbr || true
  fi

  bbr_conf='net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_fastopen=0
'
  write_text_file /etc/sysctl.d/99-linux-sh-bbr.conf "${bbr_conf}"

  if command_exists sysctl; then
    run sysctl --system
  fi
}

register_stage "bbr" "Enable BBR and conservative TCP stability tuning when supported." "stage_check_bbr" "stage_apply_bbr"
