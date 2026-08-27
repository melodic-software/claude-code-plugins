# shellcheck shell=bash
# Content-mutation disclosure guard (#1596, #3401, #3409) for hooks that may
# rewrite the edited file. One implementation of the protocol every mutating
# formatter hook previously hand-rolled: snapshot the file before the tool
# runs, compare after, name the rewrite on the user channel, and release the
# snapshot on EVERY exit arm. Hand-rolled copies drifted defect by defect —
# powershell leaked its snapshot on two arms and disclosed nothing on a
# tool-break rewrite (#3401); go-format carried the identical leak (#3405);
# ruff/biome/bash printed the disclosure as a second JSON document on runs
# that also reported findings (#3406), against the single-document stdout
# contract hook::emit_channels exists to uphold.
#
# SINGLE SOURCE OF TRUTH: lib/rewrite-guard.sh at the marketplace repo root.
# The copies at plugins/*/hooks/rewrite-guard.sh exist because installed
# plugins are cache-isolated and must be self-contained — never edit a copy.
# Edit the source and run scripts/sync-rewrite-guard.sh; CI rejects drifted
# copies. A plugin opts in by committing an initial copy of the file there.
#
# Source AFTER hook-utils.sh: hook::rewrite_disclose composes through
# hook::emit_channels.
#
# Lifecycle (one guard per hook process — these are per-invocation scripts):
#
#   hook::rewrite_guard_begin "$FILE"      # before the tool that may rewrite
#   ...run the formatter...
#   # on an arm that carries its own additionalContext:
#   hook::rewrite_take_disclosure "$FILE" "<plugin>: reformatted ..."
#   hook::emit_channels PostToolUse "$ctx" "$HOOK_REWRITE_MESSAGE"
#   # on an arm with no context of its own:
#   hook::rewrite_disclose PostToolUse "$FILE" "<plugin>: reformatted ..."
#
# The take is a DESTRUCTIVE read: the first call after begin sets
# HOOK_REWRITE_MESSAGE (empty when the file is byte-identical to the
# snapshot) and releases the snapshot; any later call resets the message to
# empty. Exactly one take per run, on the arm that emits.
#
# The release is structural, not per-arm: begin arms an EXIT trap, so an arm
# that exits without taking (or an arm added later) cannot leak the snapshot
# — the failure class #3401 and #3405 fixed one plugin at a time. The guard
# OWNS the EXIT trap; a hook that needs its own EXIT trap must chain this
# release into it. A snapshot that cannot be completed (mktemp or cp failed)
# degrades to "no disclosure": the hook still formats, take yields an empty
# message, and — unlike the hand-rolled copies, which left the mktemp file
# behind when cp failed — the orphan is removed here.

# Guard against double-sourcing.
[[ -n "${_HOOK_REWRITE_GUARD_LOADED:-}" ]] && return 0
readonly _HOOK_REWRITE_GUARD_LOADED=1

_HOOK_REWRITE_BEFORE=""
HOOK_REWRITE_MESSAGE=""

# Snapshot <file> so a rewrite can be detected and disclosed. Best-effort:
# on any failure the guard is inert and the hook proceeds undisclosed rather
# than blocked (the disclosure is advisory; the format still happens).
#   hook::rewrite_guard_begin "$FILE"
hook::rewrite_guard_begin() {
  _HOOK_REWRITE_BEFORE=""
  HOOK_REWRITE_MESSAGE=""
  local snap=""
  if snap=$(mktemp 2>/dev/null); then
    if cp "$1" "$snap" 2>/dev/null; then
      _HOOK_REWRITE_BEFORE="$snap"
      trap '[[ -n "${_HOOK_REWRITE_BEFORE:-}" ]] && rm -f "$_HOOK_REWRITE_BEFORE"' EXIT
    else
      rm -f "$snap" 2>/dev/null || true
    fi
  fi
  return 0
}

# Compare <file> against the snapshot, record <message> in
# HOOK_REWRITE_MESSAGE when it changed (empty otherwise), and release the
# snapshot. Destructive read — see the lifecycle block above. The caller
# passes HOOK_REWRITE_MESSAGE as the systemMessage argument of its ONE
# hook::emit_channels call, so a run that both rewrote and found things puts
# both channels in one JSON document.
#   hook::rewrite_take_disclosure "$FILE" "my-plugin: reformatted $(basename "$FILE") via tool."
hook::rewrite_take_disclosure() {
  local file="$1" message="$2"
  HOOK_REWRITE_MESSAGE=""
  [[ -n "$_HOOK_REWRITE_BEFORE" ]] || return 0
  if ! cmp -s "$_HOOK_REWRITE_BEFORE" "$file" 2>/dev/null; then
    HOOK_REWRITE_MESSAGE="$message"
  fi
  rm -f "$_HOOK_REWRITE_BEFORE"
  _HOOK_REWRITE_BEFORE=""
  return 0
}

# Take-and-emit for an arm that carries no additionalContext of its own:
# emits the disclosure as a systemMessage-only document, or nothing when the
# file is unchanged.
#   hook::rewrite_disclose PostToolUse "$FILE" "my-plugin: reformatted $(basename "$FILE") via tool."
hook::rewrite_disclose() {
  hook::rewrite_take_disclosure "$2" "$3"
  [[ -n "$HOOK_REWRITE_MESSAGE" ]] || return 0
  hook::emit_channels "$1" "" "$HOOK_REWRITE_MESSAGE"
}
