#!/usr/bin/env bash
# statusline-tee: transparent statusline wrapper that tees the session's
# subscription rate-limit windows to the fixed machine-scope contract path.
#
# SHELL REQUIREMENT: Bash. The statusline `command` runs in a shell; on
# Windows this script requires Git Bash (bash.exe from Git for Windows), so
# the wiring invokes it explicitly as
#   bash "<plugin-root>/scripts/statusline-tee.sh" [wrapped-command...]
# The setup skill (/rate-limit-guard:setup check) prints the exact
# settings.json edit with the resolved path.
#
# Usage:
#   statusline-tee.sh <command> [args...]  Wrap an existing statusline command:
#                                          the stdin JSON passes through to it
#                                          and its stdout and exit code are the
#                                          statusline's, byte-for-byte.
#   statusline-tee.sh                      No statusline configured: act as a
#                                          standalone minimal statusline
#                                          (model, context, both windows).
#
# Tee contract (../reference/reader-contract.md is the authoritative reader
# side): every refresh writes ~/.claude/rate-limit-guard/rate-limits.json —
# one JSON object with captured_at (ISO-8601 UTC) plus, when present on
# stdin, rate_limits and every session-distinguishing top-level field
# (session_id, session_name, and any key matching "account", so a future
# account-identifier field is adopted automatically the release it appears).
# The path is deliberately HOME-anchored and outside ${CLAUDE_PLUGIN_DATA}:
# it is a documented cross-plugin artifact seam that sibling-plugin lane
# sessions read, machine-scope by design (single-account-per-machine
# invariant — the file is last-writer-wins and carries no account id today).
#
# ATOMICITY: 3+ concurrent sessions write this one path and readers must
# never see torn JSON, so the snapshot is written to a session-unique temp
# file in the same directory and renamed over the target. On Windows,
# renaming over a target another process holds open can fail EACCES (no
# FILE_SHARE_DELETE), so the rename is retried briefly and then SKIPPED —
# the next refresh supersedes a skipped snapshot within seconds, so the skip
# is quiet by design (the durable visibility surface for a persistently
# broken tee is the setup skill's freshness probe). No tee outcome — missing
# jq, unwritable path, failed rename — ever alters the wrapped statusline's
# output or exit code.
#
# jq is required for the tee and for the standalone line; when absent the
# wrapper stays transparent and appends a visible one-line notice instead of
# silently dropping the feature.

set -uo pipefail

INPUT=""
# Bounded read of the whole stdin payload (Win32 pipes can stall before EOF;
# a truncated payload just fails jq below and tees nothing this refresh).
IFS= read -r -d '' -t 5 INPUT || true

# Write one contract snapshot. Every failure path returns 0: the tee must
# never propagate into the statusline pipeline.
tee_snapshot() {
  [[ -n "${HOME:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0 # visible notice emitted by the caller
  local dir="$HOME/.claude/rate-limit-guard"
  local target="$dir/rate-limits.json"
  mkdir -p "$dir" 2>/dev/null || return 0

  local ts payload
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 0
  payload=$(printf '%s' "$INPUT" | jq -c --arg ts "$ts" '
    {captured_at: $ts}
    + (to_entries
       | map(select(.key == "rate_limits" or .key == "session_id"
                    or .key == "session_name" or (.key | test("account"; "i"))))
       | from_entries)
  ' 2>/dev/null) || return 0
  [[ -n "$payload" ]] || return 0

  local tmp="$dir/.rate-limits.json.tmp.$$.$RANDOM"
  printf '%s\n' "$payload" >"$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    return 0
  }
  local _try
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    if mv -f "$tmp" "$target" 2>/dev/null; then
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
  rm -f "$tmp" 2>/dev/null
  return 0
}

tee_snapshot

if (($#)); then
  # Wrapped mode: transparent passthrough. The wrapped command sees the same
  # stdin bytes and owns stdout; its exit code is the wrapper's.
  printf '%s' "$INPUT" | "$@"
  rc=$?
  if ! command -v jq >/dev/null 2>&1; then
    printf 'rate-limit-guard: jq not found — rate-limit tee disabled (https://jqlang.org/download/)\n'
  fi
  exit "$rc"
fi

# Standalone mode: minimal statusline when none was configured.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$INPUT" | jq -r '
    def pct(w): ((w // {}) | if .used_percentage != null then "\(.used_percentage)%" else "-" end);
    "[\(.model.display_name // "Claude")] ctx \(.context_window.used_percentage // "-")% | 5h "
    + pct(.rate_limits.five_hour) + " | 7d " + pct(.rate_limits.seven_day)
  ' 2>/dev/null || printf 'rate-limit-guard: waiting for session data\n'
else
  printf 'rate-limit-guard: jq not found — install jq (https://jqlang.org/download/)\n'
fi
exit 0
