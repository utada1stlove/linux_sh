#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
INSPECT_ONLY=0
NON_INTERACTIVE=0
AUTO_YES=0
SELECTED_TIMEZONE="${BOOTSTRAP_TIMEZONE:-}"
ENABLE_QUIC_BLOCK="${BOOTSTRAP_QUIC_BLOCK:-}"
ONLY_STAGES=()
SKIP_STAGES=()

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

Options:
  --dry-run               Print actions without mutating the system.
  --inspect-only          Run stage inspections without applying changes.
  --non-interactive       Never prompt; keep current timezone unless --timezone is set.
  --timezone <TZ>         Set the target timezone explicitly.
  --enable-quic-block     Enable outbound UDP/443 blocking for QUIC suppression.
  --disable-quic-block    Disable outbound UDP/443 blocking.
  --only <ids>            Run only the listed comma-separated stage ids.
  --skip <ids>            Skip the listed comma-separated stage ids.
  --list-stages           Print the discovered stages and exit.
  --yes                   Assume yes for confirmation prompts.
  --help                  Show this message.
EOF
}

parse_csv() {
  local raw="$1"
  local item
  IFS=',' read -r -a items <<<"${raw}"
  for item in "${items[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -n "${item}" ]] && printf '%s\n' "${item}"
  done
}

load_stages() {
  local stage_file
  while IFS= read -r -d '' stage_file; do
    # shellcheck source=/dev/null
    source "${stage_file}"
  done < <(find "${LINUX_SH_STAGE_DIR}" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
}

parse_args() {
  local arg
  while (($# > 0)); do
    arg="$1"
    case "${arg}" in
      --dry-run)
        DRY_RUN=1
        ;;
      --inspect-only)
        INSPECT_ONLY=1
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        ;;
      --timezone)
        shift
        [[ $# -gt 0 ]] || die "--timezone requires a value."
        SELECTED_TIMEZONE="$1"
        ;;
      --enable-quic-block)
        ENABLE_QUIC_BLOCK="enabled"
        ;;
      --disable-quic-block)
        ENABLE_QUIC_BLOCK="disabled"
        ;;
      --only)
        shift
        [[ $# -gt 0 ]] || die "--only requires a comma-separated list."
        while IFS= read -r item; do
          ONLY_STAGES+=("${item}")
        done < <(parse_csv "$1")
        ;;
      --skip)
        shift
        [[ $# -gt 0 ]] || die "--skip requires a comma-separated list."
        while IFS= read -r item; do
          SKIP_STAGES+=("${item}")
        done < <(parse_csv "$1")
        ;;
      --list-stages)
        LIST_STAGES=1
        ;;
      --yes)
        AUTO_YES=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: ${arg}"
        ;;
    esac
    shift
  done
}

LIST_STAGES=0

stage_requested() {
  local stage_id="$1"
  local item

  if ((${#ONLY_STAGES[@]} > 0)); then
    for item in "${ONLY_STAGES[@]}"; do
      [[ "${item}" == "${stage_id}" ]] && break
    done
    [[ "${item:-}" == "${stage_id}" ]] || return 1
  fi

  for item in "${SKIP_STAGES[@]}"; do
    [[ "${item}" == "${stage_id}" ]] && return 1
  done

  return 0
}

list_stages() {
  local idx
  for idx in "${!STAGE_IDS[@]}"; do
    printf '%s\t%s\n' "${STAGE_IDS[$idx]}" "${STAGE_DESCRIPTIONS[$idx]}"
  done
}

run_baseline_checks() {
  local idx stage_id stage_desc check_fn
  local -n needs_apply_ref=$1

  info "Phase 1/3: baseline inspection"
  for idx in "${!STAGE_IDS[@]}"; do
    stage_id="${STAGE_IDS[$idx]}"
    stage_desc="${STAGE_DESCRIPTIONS[$idx]}"
    check_fn="${STAGE_CHECK_FUNCS[$idx]}"

    if ! stage_requested "${stage_id}"; then
      info "Skipping ${stage_id}: filtered out by --only/--skip."
      continue
    fi

    info "Inspecting ${stage_id}: ${stage_desc}"
    if "${check_fn}"; then
      needs_apply_ref["${stage_id}"]=0
      info "${stage_id}: already compliant."
    else
      needs_apply_ref["${stage_id}"]=1
      warn "${stage_id}: changes are required."
    fi
  done
}

apply_requested_stages() {
  local idx stage_id stage_desc apply_fn
  local -n needs_apply_ref=$1

  info "Phase 2/3: applying requested stages"
  for idx in "${!STAGE_IDS[@]}"; do
    stage_id="${STAGE_IDS[$idx]}"
    stage_desc="${STAGE_DESCRIPTIONS[$idx]}"
    apply_fn="${STAGE_APPLY_FUNCS[$idx]}"

    if ! stage_requested "${stage_id}"; then
      continue
    fi

    if [[ "${needs_apply_ref[$stage_id]:-0}" -eq 0 ]]; then
      info "Skipping ${stage_id}: no changes needed."
      continue
    fi

    info "Applying ${stage_id}: ${stage_desc}"
    "${apply_fn}"
  done
}

run_final_checks() {
  local idx stage_id stage_desc check_fn

  info "Phase 3/3: final inspection"
  for idx in "${!STAGE_IDS[@]}"; do
    stage_id="${STAGE_IDS[$idx]}"
    stage_desc="${STAGE_DESCRIPTIONS[$idx]}"
    check_fn="${STAGE_CHECK_FUNCS[$idx]}"

    if ! stage_requested "${stage_id}"; then
      continue
    fi

    info "Re-checking ${stage_id}: ${stage_desc}"
    "${check_fn}" || die "Stage ${stage_id} failed post-apply inspection."
  done
}

main() {
  declare -A needs_apply=()

  parse_args "$@"
  load_stages

  if ((LIST_STAGES == 1)); then
    list_stages
    exit 0
  fi

  run_baseline_checks needs_apply

  if ((INSPECT_ONLY == 1)); then
    info "Inspect-only run finished."
    exit 0
  fi

  apply_requested_stages needs_apply

  if ((DRY_RUN == 1)); then
    info "Dry-run finished. Final inspection is skipped because no changes were applied."
    exit 0
  fi

  run_final_checks
  info "Bootstrap completed successfully."
}

main "$@"
