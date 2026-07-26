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
# Time-bounded buffered read of the whole stdin payload (Win32 pipes can
# stall before EOF; a truncated payload just fails jq below and tees nothing
# this refresh). read -N buffers in 1MiB blocks and the loop drains until
# EOF, so the wrapped command receives EVERY byte regardless of payload size
# — the block size matters on Windows/MSYS pipes where the -d '' byte-at-a-
# time loop moves ~40KB/s (measured on Git Bash), and the per-block -t 5
# timeout bounds a stalled pipe without capping a large healthy payload.
# Bash below 4.1 (macOS ships 3.2) lacks -N and falls back to the delimiter
# form, which already reads to EOF, fast enough on native POSIX pipes.
# Documented boundary: on a stalled pipe (timeout mid-payload) the wrapped
# command receives only the drained bytes and fails with its own exit code;
# the tee silently skips that refresh (jq rejects the truncated JSON).
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
  _chunk=""
  while IFS= read -r -N 1048576 -t 5 _chunk; do
    INPUT+="$_chunk"
    _chunk=""
  done
  INPUT+="$_chunk" # EOF/timeout leaves the final partial block in _chunk
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
  # guard keeps it that way if the temp naming ever changes. Each candidate's
  # mtime is RE-CHECKED immediately before its unlink (a sibling session can
  # atomically replace its file between find's scan and the delete); the
  # residual microsecond race is accepted — a lost snapshot is rewritten by
  # that session's next statusline refresh and readers fail open meanwhile.
  find "$dir" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp.*' \
    -mmin +20160 -exec sh -c '
      for f in "$@"; do
        [ -n "$(find "$f" -maxdepth 0 -mmin +20160 2>/dev/null)" ] && rm -f "$f"
      done' _ {} + 2>/dev/null || true

  # Process-unique temp name with widened entropy; noclobber makes the
  # redirection refuse to follow a pre-planted symlink or overwrite any
  # pre-existing path of the same name.
  local tmp="$dir/.$sid.json.tmp.$$.$RANDOM$RANDOM"
  # Subshell umask so the snapshot lands owner-only without altering the
  # umask the wrapped statusline command inherits.
  (
    umask 077
    set -o noclobber
    printf '%s\n' "$payload" >"$tmp"
  ) 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    return 0
  }
  # Plausibility ceiling for the no-regression guard below: a target whose
  # captured_at is more than ~5 minutes ahead of this write's own timestamp
  # (clock correction, tampering) must be REPLACED, not honored — honoring
  # it would suppress every refresh until that date and wedge the session
  # in conservative mode. Lexical ISO compare; failure to compute the
  # ceiling disables the guard (write proceeds — fail toward freshness).
  local guard_ceiling
  # portability-ok: GNU-first, BSD fallback on the continuation line below (#1510)
  guard_ceiling=$(date -u -d '+5 minutes' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -v '+5M' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || guard_ceiling=""

  local _try existing_ts
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    # Never regress the snapshot: an overlapping same-session refresh may
    # have landed a NEWER captured_at while this process was still building
    # its payload (ISO-8601 UTC compares lexically). Re-checked on every
    # retry. Two residual races are ACCEPTED by design rather than
    # serialized: the check-to-rename microsecond window, and an
    # equal-second tie (captured_at is second-precision, so strict > cannot
    # order two writers born in the same second and the older may win).
    # Worst case for both is a snapshot carrying context data at most one
    # refresh/one second older than the newest — zone bands are coarse and
    # the next refresh supersedes; a lock would add a cross-platform
    # dependency (flock is absent on macOS) for no behavioral difference.
    existing_ts=$(jq -r '.captured_at // empty' "$target" 2>/dev/null) || existing_ts=""
    if [[ -n "$existing_ts" && -n "$guard_ceiling" && "$existing_ts" > "$ts" &&
      ! "$existing_ts" > "$guard_ceiling" ]]; then
      rm -f "$tmp" 2>/dev/null
      return 0
    fi
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
