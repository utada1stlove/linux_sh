#!/usr/bin/env bash

shell_bashrc_hook_present() {
  [[ -f /etc/bash.bashrc ]] &&
    grep -Fq 'linux_sh shell prompt hook' /etc/bash.bashrc
}

shell_profile_script_present() {
  [[ -f /etc/profile.d/20-linux-sh-shell.sh ]] &&
    grep -Fq 'linux_sh shell prompt' /etc/profile.d/20-linux-sh-shell.sh
}

shell_helper_present() {
  [[ -x /usr/local/lib/linux_sh/shell-helper.sh ]]
}

shell_pkg_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}\n' "${pkg}" 2>/dev/null | grep -Fq 'install ok installed'
}

shell_pkg_available() {
  local pkg="$1"
  apt-cache show "${pkg}" >/dev/null 2>&1
}

stage_check_shell() {
  local rc=0

  if shell_profile_script_present; then
    info "Shell prompt profile script is present."
  else
    warn "Shell prompt profile script is missing."
    rc=1
  fi

  if shell_helper_present; then
    info "Shell helper is present."
  else
    warn "Shell helper is missing."
    rc=1
  fi

  if shell_bashrc_hook_present; then
    info "Shell helper hook is present in /etc/bash.bashrc."
  else
    warn "Missing linux_sh shell hook in /etc/bash.bashrc"
    rc=1
  fi

  if shell_pkg_available kitty-terminfo && ! shell_pkg_installed kitty-terminfo; then
    warn "kitty-terminfo is available but not installed."
    rc=1
  fi

  if shell_pkg_available ncurses-term && ! shell_pkg_installed ncurses-term; then
    warn "ncurses-term is available but not installed."
    rc=1
  fi

  return "${rc}"
}

stage_apply_shell() {
  local shell_script helper_script

  if command_exists apt-get; then
    if shell_pkg_available kitty-terminfo && ! shell_pkg_installed kitty-terminfo; then
      run apt-get update
      run apt-get install -y kitty-terminfo
    fi

    if shell_pkg_available ncurses-term && ! shell_pkg_installed ncurses-term; then
      run apt-get update
      run apt-get install -y ncurses-term
    fi
  fi

  ensure_directory /usr/local/lib/linux_sh

  helper_script='#!/usr/bin/env bash
# linux_sh shell helper

[[ $- == *i* ]] || return 0 2>/dev/null || exit 0

linux_sh_have_terminfo() {
  local term_name="${1:-}"
  [[ -n "${term_name}" ]] || return 1
  command -v infocmp >/dev/null 2>&1 || return 1
  infocmp -x "${term_name}" >/dev/null 2>&1
}

linux_sh_fix_terminal() {
  case "${TERM:-}" in
    xterm-kitty|xterm-ghostty)
      if ! linux_sh_have_terminfo "${TERM}"; then
        export LINUX_SH_ORIGINAL_TERM="${LINUX_SH_ORIGINAL_TERM:-${TERM}}"
        export TERM=xterm-256color
      fi
      ;;
  esac
}

linux_sh_fix_terminal

export PS1="\[\e[1;38;5;220m\]\u\[\e[1;38;5;228m\]@\[\e[1;38;5;49m\]\h\[\e[0m\] \[\e[1;38;5;228m\]\w\[\e[1;38;5;213m\] [\$(date +%H:%M:%S)]\\$\[\e[0m\] "
alias ls='"'"'ls --color=auto'"'"'
'
  write_text_file /usr/local/lib/linux_sh/shell-helper.sh "${helper_script}"
  make_executable /usr/local/lib/linux_sh/shell-helper.sh

  shell_script='#!/usr/bin/env bash
# linux_sh shell prompt
if [[ $- == *i* ]]; then
  if [[ -x /usr/local/lib/linux_sh/shell-helper.sh ]]; then
    . /usr/local/lib/linux_sh/shell-helper.sh || true
  fi
fi
'

  write_text_file /etc/profile.d/20-linux-sh-shell.sh "${shell_script}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "Would ensure /etc/bash.bashrc sources linux_sh shell helper for interactive bash sessions"
  else
    if [[ ! -f /etc/bash.bashrc ]]; then
      printf '%s\n' '# system-wide .bashrc' >/etc/bash.bashrc
    fi

    if ! shell_bashrc_hook_present; then
      cat >>/etc/bash.bashrc <<'EOF'

# linux_sh shell prompt hook
if [[ $- == *i* ]] && [[ -x /usr/local/lib/linux_sh/shell-helper.sh ]]; then
  . /usr/local/lib/linux_sh/shell-helper.sh || true
fi
EOF
    fi
  fi
}

register_stage "shell" "Install the interactive shell prompt and aliases." "stage_check_shell" "stage_apply_shell"
