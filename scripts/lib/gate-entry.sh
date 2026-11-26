# shellcheck shell=bash
# GE_MODE, GE_REF, and GE_PATHS are the caller's result record.
# shellcheck disable=SC2034

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/gate-entry.sh is sourced-only\n' >&2
  exit 2
fi

if ! declare -F changed_files::verify_base >/dev/null 2>&1; then
  # shellcheck source=changed-files.sh
  . "${BASH_SOURCE[0]%/*}/changed-files.sh"
fi

if [[ -z "${GATE_ENTRY_ARMED:-}" && "${BASH_SUBSHELL:-0}" -eq 0 ]]; then
  GATE_ENTRY_ARMED=1
  trap 'exit 2' USR2
fi

gate_entry::fatal() {
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 ]]; then
    kill -USR2 "$$" 2>/dev/null || true
    sleep 5
  fi
  exit 2
}

gate_entry::require_base() {
  changed_files::verify_base "$1" && return 0
  printf '%s\n' "${2:-Error: base ref $1 is not a valid commit}" >&2
  gate_entry::fatal
}

gate_entry::classify() {
  GE_MODE=""
  GE_REF=""
  GE_PATHS=()
  if (($# == 0)); then
    return 2
  fi
  if [[ -n "${GE_FLAGS[*]-}" ]]; then
    local _ge_spec
    for _ge_spec in "${GE_FLAGS[@]}"; do
      [[ "${_ge_spec%:ref}" == "$1" ]] || continue
      GE_MODE="$1"
      shift
      if [[ "$_ge_spec" != *:ref ]]; then
        (($# == 0)) || return 2
        return 0
      fi
      (($# == 1)) || return 2
      GE_REF="$1"
      gate_entry::require_base "$GE_REF" "${GE_BAD_REF_MSG-}"
      return 0
    done
    return 2
  fi
  case "$1" in
  --all)
    (($# == 1)) || return 2
    GE_MODE=all
    ;;
  --paths)
    shift
    (($# > 0)) || return 2
    GE_MODE=paths
    GE_PATHS=("$@")
    ;;
  -*)
    return 2
    ;;
  *)
    GE_REF="$1"
    (($# == 1)) || return 2
    GE_MODE=base
    gate_entry::require_base "$GE_REF" "${GE_BAD_REF_MSG-}"
    ;;
  esac
  return 0
}

gate_entry::collect_changed() {
  local _ge_out_name="$1"
  local _ge_base="$2"
  shift 2
  gate_entry::require_base "$_ge_base"
  changed_files::into "$_ge_out_name" "$_ge_base" "$@" || gate_entry::fatal
}

gate_entry::finish() {
  case "${1-}" in
  0 | 1) exit "$1" ;;
  *) exit 2 ;;
  esac
}
