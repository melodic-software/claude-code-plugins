# shellcheck shell=bash
# GE_MODE, GE_REF, and GE_PATHS are the caller's result record.
# shellcheck disable=SC2034
# Shared entry for repo-tooling gates under scripts/. Sourced, never executed.
#
# Owns four steps the gates otherwise re-derive:
#   mode dispatch          <base-ref> | --all | --paths FILE...
#   base-ref validation    in this shell, via changed_files::verify_base
#   target discovery       nameref fill; a failed diff is not an empty set
#   exit mapping           0 pass, 1 findings, anything else 2
#
# A fatal raised inside a subshell (mapfile, process substitution, command
# substitution) signals this shell on USR2. The trap exits 2, so the #3377
# shape — an unresolvable ref swallowed as an empty target list — cannot
# report a pass. --all and --paths never consult a ref.
#
# Adoption: classify and finish are used by check-shell-portability,
# check-skill-portability, and check-skill-precompute-compose. Only require_base
# is used by check-guardrails-ps-differential. affected-tests,
# check-changed-skills, check-docs-only, check-changelog-parity,
# check-contract-slice-prune, check-skill-description-voice,
# check-stale-base-overlap, and check-vendor-version-bump still dispatch modes
# and map exits themselves; the
# #3413 triage brief scoped out adding modes to other gates.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/gate-entry.sh is sourced-only\n' >&2
  exit 2
fi

if ! declare -F changed_files::verify_base >/dev/null 2>&1; then
  # shellcheck source=changed-files.sh
  . "${BASH_SOURCE[0]%/*}/changed-files.sh"
fi

# Parent shells only. A subshell inherits the variable and must not replace
# the trap; a fresh process does not inherit an unexported variable and arms
# its own. USR2 is not the EXIT trap, so a gate's cleanup trap stays put.
if [[ -z "${GATE_ENTRY_ARMED:-}" && "${BASH_SUBSHELL:-0}" -eq 0 ]]; then
  GATE_ENTRY_ARMED=1
  trap 'exit 2' USR2
fi

# gate_entry::fatal
# Exit 2. From a subshell, ask the parent shell to exit 2 and wait until it
# does. Sleeping is what keeps a process substitution from returning before
# the signal is delivered; the parent exit reaps it.
gate_entry::fatal() {
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 ]]; then
    kill -USR2 "$$" 2>/dev/null || true
    sleep 5
    exit 2
  fi
  exit 2
}

# gate_entry::require_base <ref> [message]
# 0 when <ref> is a commit. Otherwise print <message> (or the shared
# diagnostic) and exit 2, including when the caller is a subshell.
gate_entry::require_base() {
  local _ge_ref="$1"
  local _ge_msg="${2-}"
  if changed_files::verify_base "$_ge_ref"; then
    return 0
  fi
  if [[ -n "$_ge_msg" ]]; then
    printf '%s\n' "$_ge_msg" >&2
  else
    printf 'Error: base ref %s is not a valid commit\n' "$_ge_ref" >&2
  fi
  gate_entry::fatal
}

# gate_entry::classify [args...]
# Sets GE_MODE to all, paths, or base. GE_REF is the base ref in base mode.
# GE_PATHS is the file list in paths mode. Returns 2 on a usage error and
# does not exit, so the caller can print its own usage line. An unresolvable
# base ref exits 2 from this shell. --all and --paths do not call git.
gate_entry::classify() {
  GE_MODE=""
  GE_REF=""
  GE_PATHS=()
  if (($# == 0)); then
    return 2
  fi
  case "$1" in
  --all)
    shift
    if (($# != 0)); then
      return 2
    fi
    GE_MODE=all
    ;;
  --paths)
    shift
    if (($# == 0)); then
      return 2
    fi
    GE_MODE=paths
    GE_PATHS=("$@")
    ;;
  -*)
    return 2
    ;;
  *)
    GE_REF="$1"
    shift
    if (($# != 0)); then
      return 2
    fi
    GE_MODE=base
    gate_entry::require_base "$GE_REF"
    ;;
  esac
  return 0
}

# gate_entry::collect_changed <out-array> <base> [changed_files::into args...]
# Fills <out-array> from the shared diff. A resolvable base with no changes
# returns 0 with an empty array. A failed diff or an unresolvable base exits 2.
# The two are not the same result.
gate_entry::collect_changed() {
  local _ge_out_name="$1"
  local _ge_base="$2"
  shift 2
  gate_entry::require_base "$_ge_base"
  # Pass the caller's array name straight through. A nameref in this frame
  # would sit between changed_files::into and that array, and a nameref that
  # points at a nameref comes back empty.
  if ! changed_files::into "$_ge_out_name" "$_ge_base" "$@"; then
    gate_entry::fatal
  fi
  return 0
}

# gate_entry::finish <status>
# The 0/1/2 map. 0 and 1 pass through. Every other status, including an
# omitted one, is a fail-closed 2.
gate_entry::finish() {
  case "${1-}" in
  0) exit 0 ;;
  1) exit 1 ;;
  *) exit 2 ;;
  esac
}
