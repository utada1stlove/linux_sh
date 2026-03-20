#!/usr/bin/env bash

stage_check_shell() {
  if [[ -f /etc/profile.d/20-linux-sh-shell.sh ]] && grep -Fq 'linux_sh shell prompt' /etc/profile.d/20-linux-sh-shell.sh; then
    info "Shell prompt configuration is present."
    return 0
  fi

  warn "Shell prompt configuration is missing."
  return 1
}

stage_apply_shell() {
  local shell_script

  shell_script='#!/usr/bin/env bash
# linux_sh shell prompt
if [[ $- == *i* ]]; then
  export PS1="\[\e[1;38;5;220m\]\u\[\e[1;38;5;228m\]@\[\e[1;38;5;49m\]\h\[\e[0m\] \[\e[1;38;5;228m\]\w\[\e[1;38;5;213m\] [\$(date +%H:%M:%S)]\\$\[\e[0m\] "
  alias ls='"'"'ls --color=auto'"'"'
fi
'

  write_text_file /etc/profile.d/20-linux-sh-shell.sh "${shell_script}"
}

register_stage "shell" "Install the interactive shell prompt and aliases." "stage_check_shell" "stage_apply_shell"
