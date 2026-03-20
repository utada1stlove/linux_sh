#!/usr/bin/env bash

bbr_virtualization() {
  if command_exists systemd-detect-virt; then
    systemd-detect-virt --container 2>/dev/null || true
  fi
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
    [[ -r /proc/sys/net/ipv4/tcp_congestion_control ]]
}

stage_check_bbr() {
  local current_qdisc current_cc

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

  if [[ "${current_qdisc}" == "fq" ]] &&
    [[ "${current_cc}" == "bbr" ]] &&
    [[ -f /etc/sysctl.d/99-linux-sh-bbr.conf ]]; then
    info "BBR is configured."
    return 0
  fi

  warn "BBR is not fully configured."
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
'
  write_text_file /etc/sysctl.d/99-linux-sh-bbr.conf "${bbr_conf}"

  if command_exists sysctl; then
    run sysctl --system
  fi
}

register_stage "bbr" "Enable BBR when the kernel and virtualization type allow it." "stage_check_bbr" "stage_apply_bbr"
