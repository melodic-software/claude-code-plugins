# shellcheck shell=bash
# Gate entry protocol (sourceable).
#
# Owns invocation mode, the parent-shell base-ref check, and the fail-closed
# exit. Builds on changed_files::verify_base. A check that runs inside a
# subshell still terminates the gate: bash keeps $$ as the parent pid, and
# the USR2 trap installed here exits 2.

if [[ -z "$(trap -p USR2)" ]]; then
  # shellcheck disable=SC2064
  trap 'exit 2' USR2
fi

# shellcheck source=changed-files.sh
source "${BASH_SOURCE[0]%/*}/changed-files.sh"

# gate_entry::fail <code> <message>
# Exit <code> from the gate process, including when called from a subshell.
gate_entry::fail() {
  local code="$1"
  shift
  printf '%s\n' "$*" >&2
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 ]]; then
    kill -s USR2 "$$" 2>/dev/null || true
    exit "$code"
  fi
  exit "$code"
}

# gate_entry::require_commit <ref> <message>
# Return 0 when <ref> is a commit. Otherwise terminate the gate with exit 2.
gate_entry::require_commit() {
  local ref="$1"
  shift
  if changed_files::verify_base "$ref"; then
    return 0
  fi
  gate_entry::fail 2 "$*"
}

# gate_entry::begin <mode>
# mode is --all, --paths, or a base ref.
# --all and --paths do not consult a ref. A ref that does not resolve exits 2.
# Sets GATE_ENTRY_MODE to all, paths, or ref.
gate_entry::begin() {
  local mode="${1:-}"
  GATE_ENTRY_MODE=""
  case "$mode" in
  --all)
    GATE_ENTRY_MODE=all
    return 0
    ;;
  --paths)
    GATE_ENTRY_MODE=paths
    return 0
    ;;
  "")
    gate_entry::fail 2 "gate-entry: mode required (--all, --paths, or a base ref)"
    ;;
  *)
    gate_entry::require_commit "$mode" "gate-entry: base ref not resolvable: $mode"
    # callers read the mode after begin returns
    # shellcheck disable=SC2034
    GATE_ENTRY_MODE=ref
    return 0
    ;;
  esac
}
