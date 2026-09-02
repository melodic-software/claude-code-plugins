#!/usr/bin/env bash
# PostCompact hook: persist an evidence-degraded marker for the session.
#
# Closes the reader contract's documented gap ("Zone is NOT a compaction
# indicator"): a compacted session's percentage resets downward while the
# evidence in its conversational context is already gone, and the snapshot
# alone cannot tell a consumer that compaction happened. This hook writes a
# sibling marker file next to the session's snapshot:
#
#   ~/.claude/context-guard/context/<session_id>.compacted
#   {"compacted_at":"<ISO-8601 UTC>","trigger":"manual|auto|unknown",
#    "hook_event_name":"PostCompact"}
#
# The marker is part of the cross-plugin artifact seam (fixed HOME-anchored
# contract path, deliberately OUTSIDE ${CLAUDE_PLUGIN_DATA}); consumers
# presence-check it and treat the session as evidence-degraded regardless of
# a green zone (reader contract, "Evidence-degraded marker"). Last-write-
# wins per session: only the most recent compaction matters.
#
# SIDE-EFFECT-ONLY by upstream contract: PostCompact has no decision control
# (verified 2026-08-10 against code.claude.com/docs/en/hooks), so this
# hook's one job is the marker. jq-FREE by design, mirroring the
# rate-limit-guard StopFailure recorder: the fields are regex-extracted so a
# degraded environment still records. It also resets the blocking gate's
# grace counter — compaction opens a fresh window.
#
# Kill switch: context_guard_hooks_enabled userConfig boolean, read via the
# CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED hook-process mirror.

set -uo pipefail

# Hook directory by parameter expansion, never `dirname`: two sources meant two
# processes before any work. The `.` fallback reproduces dirname's own answer
# for a bare, slash-free invocation.
CG_DIR=${BASH_SOURCE[0]%/*}
[[ "$CG_DIR" == "${BASH_SOURCE[0]}" ]] && CG_DIR=.
# shellcheck source=hook-utils.sh
source "$CG_DIR/hook-utils.sh"
# shellcheck source=payload.sh
source "$CG_DIR/payload.sh"

hook::check_enabled "CONTEXT_GUARD_HOOKS"

START_EPOCH=${EPOCHREALTIME:-0}

# A missing or incomplete payload degrades the record, never suppresses it.
# Chunked reader: PostCompact carries the FULL compact_summary, so a single
# bounded read times out on the normal case, not an edge (measured ~80KB
# already lost on Git Bash pipes).
INPUT=$(cg::read_payload) || INPUT=""

SESSION=""
if [[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  SESSION="${BASH_REMATCH[1]}"
fi
# silent-skip-ok: without a session id there is no snapshot to mark, and the
# marker path cannot be keyed; the filename character class also provides
# path containment.
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

TRIGGER="unknown"
if [[ "$INPUT" =~ \"trigger\"[[:space:]]*:[[:space:]]*\"(manual|auto)\" ]]; then
  TRIGGER="${BASH_REMATCH[1]}"
fi

# silent-skip-ok: no HOME means no resolvable contract path anywhere on this
# host; PostCompact is side-effect-only with no decision channel, and the
# setup skill's check probe is the visibility surface for a broken contract
# path.
[[ -n "${HOME:-}" ]] || exit 0
CTX_DIR="$HOME/.claude/context-guard/context"
# `mkdir -p` on an existing directory already exited 0, so the guard changes no
# outcome and skips the process on every compaction after the first. The chmod
# is NOT guarded: it repairs permissions on a shared contract directory this
# hook does not own, and skipping it would make that repair depend on which
# process created the directory.
[[ -d "$CTX_DIR" ]] || mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
chmod 700 "$HOME/.claude/context-guard" "$CTX_DIR" 2>/dev/null || true
umask 077

# printf's %()T format instead of `date`, the same idiom hook-utils uses for
# its telemetry timestamp: identical string, no process. TZ=UTC overrides the
# local zone so the trailing Z is not a lie. The %()T conversion arrived in
# bash 4.2, and stock macOS ships 3.2, which these hooks support: there printf
# fails and binds nothing, so the timestamp falls back to the `date` this line
# replaced rather than recording an empty compacted_at. On 4.2+ the fallback is
# never reached and the marker still costs no clock process.
ts=""
if ! TZ=UTC printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || [[ -z "$ts" ]]; then
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""
fi

marker='{"compacted_at":"'"$(hook::json_escape "$ts")"'","trigger":"'"$TRIGGER"'","hook_event_name":"PostCompact"}'
target="$CTX_DIR/$SESSION.compacted"
tmp="$CTX_DIR/$SESSION.compacted.tmp.$$"
# Track the write-and-rename result explicitly: telemetry status must reflect
# whether the marker was actually recorded, not just whether the hook ran.
# marker_ok stays 0 (and status reports "error") whenever the temp-file write,
# the atomic rename, or the contract path itself leaves consumers without a
# readable marker — operators must never be told "ok" for a marker consumers
# will never see.
marker_ok=0
if printf '%s\n' "$marker" >"$tmp" 2>/dev/null; then
  # A directory at the contract path makes `mv` SUCCEED by moving the temp
  # file inside it, stranding the marker where no consumer looks. Refuse the
  # rename up front rather than report a false "ok" (and rather than discover
  # it afterwards, which would leave the temp file littered in that
  # directory).
  if [[ -d "$target" ]]; then
    rm -f "$tmp" 2>/dev/null
  elif mv -f "$tmp" "$target" 2>/dev/null; then
    marker_ok=1
  else
    rm -f "$tmp" 2>/dev/null
  fi
fi

# Prune stale sibling markers with the same 14-day cutoff the tee applies to
# snapshots — the shared contract dir must not grow unboundedly, and the
# tee's own sweep matches *.json only.
find "$CTX_DIR" -maxdepth 1 -name '*.compacted' -mmin +20160 -exec rm -f {} + 2>/dev/null || true

# Compaction opens a fresh window: re-arm the blocking gate's grace budget.
STATE_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/context-guard}/state"
# The counter only exists in blocking mode, so on the default advisory posture
# this `rm` was a process spawned to delete nothing. `rm -f` on an absent path
# already succeeded, so the guard changes no outcome.
if [[ -e "$STATE_DIR/$SESSION.gate-count" ]]; then
  rm -f "$STATE_DIR/$SESSION.gate-count" 2>/dev/null || true
fi

# SIDE-EFFECT-ONLY contract still holds: PostCompact has no decision control,
# so this always exits 0 regardless of marker_ok — only the telemetry status
# reports the real outcome.
telemetry_status="ok"
((marker_ok)) || telemetry_status="error"
hook::emit_telemetry "post-compact-mark" "PostCompact" "$telemetry_status" "$START_EPOCH" \
  '{"trigger":"'"$TRIGGER"'"}'
exit 0
