#!/usr/bin/env bash

vnstat_primary_iface() {
  default_interface
}

vnstat_db_has_iface() {
  local iface="$1"
  vnstat --dbiflist 1 2>/dev/null | tr ' ' '\n' | grep -Fx "${iface}" >/dev/null 2>&1
}

vnstat_service_ready() {
  command_exists systemctl &&
    systemctl is-enabled --quiet vnstat.service &&
    systemctl is-active --quiet vnstat.service
}

vnstat_bashrc_hook_present() {
  [[ -f /etc/bash.bashrc ]] &&
    grep -Fq 'linux_sh vnstat login hook' /etc/bash.bashrc
}

stage_check_vnstat() {
  local iface
  local rc=0

  if ! command_exists vnstat; then
    warn "vnstat is not installed."
    return 1
  fi

  iface="$(vnstat_primary_iface)"
  if [[ -z "${iface}" ]]; then
    warn "Unable to determine the default network interface."
    return 1
  fi

  info "vnstat interface: ${iface}"

  if ! vnstat_db_has_iface "${iface}"; then
    warn "vnstat database has not been initialized for ${iface}."
    rc=1
  fi

  if ! vnstat_service_ready; then
    warn "vnstat.service is not enabled and active."
    rc=1
  fi

  [[ -x /usr/local/lib/linux_sh/vnstat-login.sh ]] || {
    warn "Missing /usr/local/lib/linux_sh/vnstat-login.sh"
    rc=1
  }

  [[ -f /etc/profile.d/40-linux-sh-vnstat.sh ]] || {
    warn "Missing /etc/profile.d/40-linux-sh-vnstat.sh"
    rc=1
  }

  vnstat_bashrc_hook_present || {
    warn "Missing linux_sh vnstat hook in /etc/bash.bashrc"
    rc=1
  }

  return "${rc}"
}

stage_apply_vnstat() {
  local helper_script profile_script iface

  iface="$(vnstat_primary_iface)"
  if [[ -z "${iface}" ]]; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      iface="eth0"
      warn "Default interface could not be detected on this host; dry-run will use ${iface} as a placeholder."
    else
      die "Unable to determine the default network interface for vnstat."
    fi
  fi

  if command_exists systemctl; then
    run systemctl enable --now vnstat.service
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    run vnstat --add -i "${iface}"
  elif ! vnstat_db_has_iface "${iface}"; then
    run vnstat --add -i "${iface}"
  fi

  if command_exists systemctl; then
    run systemctl restart vnstat.service
  fi

  ensure_directory /usr/local/lib/linux_sh
  ensure_directory /var/tmp/linux_sh

  helper_script='#!/usr/bin/env bash
set -Eeuo pipefail

[[ $- == *i* ]] || exit 0
[[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || exit 0
[[ "${LINUX_SH_VNSTAT_SHOWN:-0}" == "1" ]] && exit 0
export LINUX_SH_VNSTAT_SHOWN=1

iface="$(ip -o route show default 2>/dev/null | awk '"'"'NR == 1 { print $5 }'"'"')"
[[ -n "${iface}" ]] || exit 0

printf "\n[linux_sh] Traffic summary for %s (last 24h)\n" "${iface}"
vnstat -i "${iface}" -h 24 || exit 0

if command -v vnstati >/dev/null 2>&1; then
  cache_dir="/var/tmp/linux_sh"
  mkdir -p "${cache_dir}"
  image_path="${cache_dir}/vnstat-${iface}-24h.png"
  if vnstati -i "${iface}" -h 24 -o "${image_path}" >/dev/null 2>&1; then
    printf "[linux_sh] 24h graph: %s\n" "${image_path}"
  fi
fi

printf "\n"'
  write_text_file /usr/local/lib/linux_sh/vnstat-login.sh "${helper_script}"
  make_executable /usr/local/lib/linux_sh/vnstat-login.sh

  profile_script='#!/usr/bin/env bash
if [[ $- == *i* ]] && [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] && [[ -x /usr/local/lib/linux_sh/vnstat-login.sh ]]; then
  /usr/local/lib/linux_sh/vnstat-login.sh || true
fi
'
  write_text_file /etc/profile.d/40-linux-sh-vnstat.sh "${profile_script}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "Would ensure /etc/bash.bashrc sources linux_sh vnstat helper for SSH sessions"
  else
    if [[ ! -f /etc/bash.bashrc ]]; then
      printf '%s\n' '# system-wide .bashrc' >/etc/bash.bashrc
    fi

    if ! vnstat_bashrc_hook_present; then
      cat >>/etc/bash.bashrc <<'EOF'

# linux_sh vnstat login hook
if [[ $- == *i* ]] && [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] && [[ -x /usr/local/lib/linux_sh/vnstat-login.sh ]]; then
  /usr/local/lib/linux_sh/vnstat-login.sh || true
fi
EOF
    fi
  fi
}

register_stage "vnstat" "Enable vnstat and show SSH login traffic summaries." "stage_check_vnstat" "stage_apply_vnstat"
