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
# (session_id, session_name, and any key whose name contains "account", so a
# future account-identifier field is adopted automatically only when it
# arrives under a top-level key of that shape; every other shape needs a
# writer change).
# The path is deliberately HOME-anchored and outside ${CLAUDE_PLUGIN_DATA}:
# it is a documented cross-plugin artifact seam that sibling-plugin lane
# sessions read, machine-scope by design (the file is last-writer-wins and
# carries no account id today — loop-lane §6 owns that gap's framing).
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
# TEMP-FILE RECLAIM: a temp file can outlive this process. Claude Code
# "cancels the in-flight script" when a new update arrives while this one is
# still running (https://code.claude.com/docs/en/statusline), and a
# cancellation between the write and the rename leaves the temp behind — no
# failed rm is needed to explain it, the process simply never reaches the
# reclaim line. Two mechanisms, because neither is sufficient alone: a trap
# reclaims on exit and on a catch-able signal, and an age-filtered sweep of
# leftover siblings recovers what a SIGKILL, a crash, or power loss leaves,
# which no trap can. The sweep costs nothing on a clean directory — a glob
# decides whether to spawn anything at all — and it cannot race a live
# sibling, since the normal write-to-rename window is sub-second while the
# age floor is a minute.
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

# Path of the temp file currently in flight, for the reclaim traps below. A
# global rather than the function's local: the trap body is evaluated when the
# trap fires, by which time the function's locals are gone.
TEE_TMP=""

reclaim_tee_tmp() {
  [[ -n "$TEE_TMP" ]] && rm -f "$TEE_TMP" 2>/dev/null
  TEE_TMP=""
  return 0
}

# Lock directory currently held (see acquire_tee_lock below); a global for
# the same trap-lifetime reason as TEE_TMP, and defined before the trap is
# installed so an early exit never references an undefined function.
TEE_LOCK=""

release_tee_lock() {
  [[ -n "$TEE_LOCK" ]] && rmdir "$TEE_LOCK" 2>/dev/null
  TEE_LOCK=""
  return 0
}

# The signal traps exit rather than reclaiming directly, so the EXIT trap stays
# the single reclaim path. Exiting is also the right response to a cancelling
# signal: this refresh's snapshot is already superseded by the update that
# cancelled it.
trap 'reclaim_tee_tmp; release_tee_lock' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# Reclaim temp siblings left by a process that never got to clean up. Only
# files older than the age floor are touched, so a concurrent session's live
# temp — sub-second between write and rename — is never a candidate.
#
# The glob runs first and decides whether to spawn at all: on a clean
# directory, which is every refresh in normal operation, this costs zero
# processes on a path that already runs at two to four times the statusline
# debounce interval.
sweep_stale_tee_temps() {
  local dir="$1" candidate
  for candidate in "$dir"/.rate-limits.json.tmp.*; do
    [[ -e "$candidate" ]] || continue
    find "$dir" -maxdepth 1 -type f -name '.rate-limits.json.tmp.*' \
      -mmin +1 -exec rm -f {} + 2>/dev/null || true
    return 0
  done
  return 0
}

# Serialize the preservation decision with the rename. Check-then-write
# without mutual exclusion lets a windowless writer pass its check, lose the
# CPU to a window-bearing writer's rename, and then clobber the fresh windows
# anyway — concurrent sessions are the normal operating model here. The lock
# is a directory (mkdir-as-lock is atomic on every platform this runs on,
# including Git Bash on Windows, where flock is unavailable). A holder killed
# between mkdir and rmdir would leave the lock forever, so a contender steals
# any lock older than the same one-minute age floor the temp sweep uses —
# far above the sub-second hold time of a live writer. The release side lives
# with the traps above.
acquire_tee_lock() {
  local dir="$1" lock="$1/.rate-limits.json.lock" _try
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    if mkdir "$lock" 2>/dev/null; then
      TEE_LOCK="$lock"
      return 0
    fi
    find "$dir" -maxdepth 1 -type d -name '.rate-limits.json.lock' \
      -mmin +1 -exec rmdir {} + 2>/dev/null || true
    sleep 0.1 2>/dev/null || true
  done
  return 1
}

# Write one contract snapshot. Every failure path returns 0: the tee must
# never propagate into the statusline pipeline.
tee_snapshot() {
  [[ -n "${HOME:-}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0 # visible notice emitted by the caller
  local dir="$HOME/.claude/rate-limit-guard"
  local target="$dir/rate-limits.json"
  mkdir -p "$dir" 2>/dev/null || return 0
  # Owner-only contract dir: keeps other local users from pre-planting
  # symlinks or reading the snapshot. Best-effort (no-op on filesystems
  # without POSIX modes, e.g. Windows ACL volumes under Git Bash).
  chmod 700 "$dir" 2>/dev/null || true

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

  # Window-bearing is a structural property — jq's has(), never a substring
  # test: a forwarded value that merely contains the string "rate_limits"
  # (e.g. "session_name":"rate_limits") must not count as window-bearing and
  # overwrite a snapshot holding real windows.
  local has_windows=false
  jq -e 'has("rate_limits")' >/dev/null 2>&1 <<<"$payload" && has_windows=true

  # Sweep before any early return: a machine where only windowless sessions
  # remain active would otherwise skip below on every refresh and never
  # reclaim the orphan a killed window-bearing session left behind.
  sweep_stale_tee_temps "$dir"

  # All writers take the lock around [check+]rename — serialization needs
  # both parties. On acquisition failure the windowless writer skips its
  # write (nothing precious is lost; the reader treats absence reactively),
  # while the window-bearing writer proceeds unlocked: its payload carries
  # data, and last-writer-wins between two window-bearing snapshots is the
  # pre-existing contract.
  if ! acquire_tee_lock "$dir"; then
    [[ "$has_windows" == true ]] || return 0
  fi

  # A session with no windows — API-key or enterprise auth — must not overwrite
  # a snapshot that HAS them. The reader contract routes a snapshot missing
  # rate_limits to whole-guard reactive-only, and this write would carry a FRESH
  # captured_at, so consumers would never see "stale" and would instead see a
  # current snapshot with no data: up to the contract's full 10-minute staleness
  # budget of usable proactive data destroyed on a mixed-auth machine, silently.
  # A target jq cannot parse counts as windowless — torn or corrupt content is
  # exactly what an atomic overwrite should replace.
  if [[ "$has_windows" != true && -f "$target" ]]; then
    if jq -e 'has("rate_limits")' "$target" >/dev/null 2>&1; then
      release_tee_lock
      return 0
    fi
  fi

  local tmp="$dir/.rate-limits.json.tmp.$$.$RANDOM"
  TEE_TMP="$tmp"
  # Subshell umask so the snapshot lands owner-only without altering the
  # umask the wrapped statusline command inherits.
  (
    umask 077
    printf '%s\n' "$payload" >"$tmp"
  ) 2>/dev/null || {
    reclaim_tee_tmp
    release_tee_lock
    return 0
  }
  local _try
  # shellcheck disable=SC2034  # bounded-retry counter; the value itself is unused
  for _try in 1 2 3; do
    if mv -f "$tmp" "$target" 2>/dev/null; then
      # The temp path is the target now; clear it so the EXIT trap cannot
      # reclaim a name that no longer refers to this refresh's file.
      TEE_TMP=""
      release_tee_lock
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
  reclaim_tee_tmp
  release_tee_lock
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
