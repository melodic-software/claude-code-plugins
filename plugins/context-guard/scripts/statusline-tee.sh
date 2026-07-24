#!/usr/bin/env bash
# statusline-tee: transparent statusline wrapper that tees each session's
# context-window fields to a per-session snapshot file.
#
# SHELL REQUIREMENT: Bash. The statusline `command` runs in a shell; on
# Windows this script requires Git Bash (bash.exe from Git for Windows), so
# the wiring invokes it explicitly as
#   bash "<plugin-root>/scripts/statusline-tee.sh" [wrapped-command...]
# The setup skill (/context-guard:setup check) prints the exact
# settings.json edit with the resolved path.
#
# Usage:
#   statusline-tee.sh <command> [args...]  Wrap an existing statusline command:
#                                          the stdin JSON passes through to it
#                                          and its stdout and exit code are the
#                                          statusline's, byte-for-byte.
#   statusline-tee.sh                      No statusline configured: act as a
#                                          standalone minimal statusline
#                                          (model + context usage).
#
# Tee contract (../reference/reader-contract.md is the authoritative reader
# side): every refresh writes
#   ~/.claude/context-guard/context/<session_id>.json
# — one JSON object with captured_at (ISO-8601 UTC), session_id, and, when
# present on stdin, the context_window object copied VERBATIM (field
# additions upstream flow through without a plugin change; null fields are
# the reader's concern). The path is deliberately HOME-anchored and outside
# ${CLAUDE_PLUGIN_DATA}: it is a documented cross-plugin artifact seam that
# sibling-plugin sessions read, PER-SESSION by design (no last-writer-wins
# collapse across sessions).
#
# PATH CONTAINMENT: session_id is used as a filename, so it is accepted only
# when it matches ^[A-Za-z0-9_-]+$ — anything else (absent, path separators,
# dots, spaces) skips the tee entirely for that refresh. The wrapped
# statusline is unaffected.
#
# PRUNING (implementation detail, not contract): sibling *.json snapshots
# older than 14 days are deleted on write. The cutoff is deliberately far
# larger than the reader contract's 10-minute staleness window so a
# live-but-idle session's snapshot is never deleted, and in-flight
# .tmp.* files are never touched.
#
# ATOMICITY: concurrent refreshes of the same session and cross-session
# sibling writes share one directory, and readers must never see torn JSON,
# so the snapshot is written to a process-unique temp file in the same
# directory and renamed over the target. On Windows, renaming over a target
# another process holds open can fail EACCES (no FILE_SHARE_DELETE), so the
# rename is retried briefly and then SKIPPED — the next refresh supersedes a
# skipped snapshot within seconds, so the skip is quiet by design (the
# durable visibility surface for a persistently broken tee is the setup
# skill's freshness probe). No tee outcome — missing jq, unwritable path,
# failed rename — ever alters the wrapped statusline's output or exit code.
#
# jq is required for the tee and for the standalone line; when absent the
# wrapper stays transparent and appends a visible one-line notice instead of
# silently dropping the feature.

set -uo pipefail

INPUT=""
# Bounded buffered read of the whole stdin payload (Win32 pipes can stall
# before EOF; a truncated payload just fails jq below and tees nothing this
# refresh). read -N buffers in blocks, which matters on Windows/MSYS pipes
# where the -d '' byte-at-a-time loop moves ~40KB/s and can truncate a large
# payload at the timeout (measured on Git Bash); Bash below 4.1 (macOS ships
# 3.2) lacks -N and falls back to the delimiter form, fast enough on native
# POSIX pipes. 1MiB bound: statusline payloads are a few KB.
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
  IFS= read -r -N 1048576 -t 5 INPUT || true
else
  IFS= read -r -d '' -t 5 INPUT || true
fi

# Write one per-session contract snapshot. Every failure path returns 0: the
# tee must never propagate into the statusline pipeline.
tee_snapshot() {
  [[ -n "${HOME:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0 # visible notice emitted by the caller

  # Extract + sanitize the session id BEFORE any filesystem work: it becomes
  # the snapshot filename, so only [A-Za-z0-9_-] is accepted.
  local sid
  sid=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || return 0
  [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 0

  local dir="$HOME/.claude/context-guard/context"
  local target="$dir/$sid.json"
  mkdir -p "$dir" 2>/dev/null || return 0
  # Owner-only contract dir: keeps other local users from pre-planting
  # symlinks or reading the snapshots. Best-effort (no-op on filesystems
  # without POSIX modes, e.g. Windows ACL volumes under Git Bash).
  chmod 700 "$dir" 2>/dev/null || true

  local ts payload
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 0
  payload=$(printf '%s' "$INPUT" | jq -c --arg ts "$ts" '
    {captured_at: $ts, session_id: .session_id}
    + (if has("context_window") then {context_window} else {} end)
  ' 2>/dev/null) || return 0
  [[ -n "$payload" ]] || return 0

  # Prune stale sibling snapshots (14 days ≫ the reader contract's 10-minute
  # staleness window — a live-but-idle session survives). Pattern *.json
  # never matches the dot-prefixed .*.tmp.* in-flight files; the explicit
  # guard keeps it that way if the temp naming ever changes.
  find "$dir" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp.*' \
    -mmin +20160 -exec rm -f {} + 2>/dev/null || true

  local tmp="$dir/.$sid.json.tmp.$$.$RANDOM"
  # Subshell umask so the snapshot lands owner-only without altering the
  # umask the wrapped statusline command inherits.
  (
    umask 077
    printf '%s\n' "$payload" >"$tmp"
  ) 2>/dev/null || {
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
  # stdin bytes and owns stdout; its exit code is the wrapper's. pipefail is
  # dropped for exactly this pipeline: a wrapped command that never reads
  # stdin closes the pipe under printf, and pipefail would surface printf's
  # SIGPIPE (141) instead of the wrapped command's own exit code. printf's
  # stderr is silenced for the same case (bash prints a broken-pipe notice).
  set +o pipefail
  printf '%s' "$INPUT" 2>/dev/null | "$@"
  rc=$?
  set -o pipefail
  if ! command -v jq >/dev/null 2>&1; then
    printf 'context-guard: jq not found — context tee disabled (https://jqlang.org/download/)\n'
  fi
  exit "$rc"
fi

# Standalone mode: minimal statusline when none was configured.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$INPUT" | jq -r '
    "[\(.model.display_name // "Claude")] ctx \(.context_window.used_percentage // "-")%"
  ' 2>/dev/null || printf 'context-guard: waiting for session data\n'
else
  printf 'context-guard: jq not found — install jq (https://jqlang.org/download/)\n'
fi
exit 0
