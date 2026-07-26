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
# (verified 2026-07-26 against code.claude.com/docs/en/hooks), so this
# hook's one job is the marker. jq-FREE by design, mirroring the
# rate-limit-guard StopFailure recorder: the fields are regex-extracted so a
# degraded environment still records. It also resets the blocking gate's
# grace counter — compaction opens a fresh window.
#
# Kill switch: context_guard_hooks_enabled userConfig boolean, read via the
# CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED hook-process mirror.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=payload.sh
source "$(dirname "${BASH_SOURCE[0]}")/payload.sh"

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
mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
chmod 700 "$HOME/.claude/context-guard" "$CTX_DIR" 2>/dev/null || true
umask 077

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""

marker='{"compacted_at":"'"$(hook::json_escape "$ts")"'","trigger":"'"$TRIGGER"'","hook_event_name":"PostCompact"}'
tmp="$CTX_DIR/$SESSION.compacted.tmp.$$"
if printf '%s\n' "$marker" >"$tmp" 2>/dev/null; then
  mv -f "$tmp" "$CTX_DIR/$SESSION.compacted" 2>/dev/null || rm -f "$tmp" 2>/dev/null
fi

# Prune stale sibling markers with the same 14-day cutoff the tee applies to
# snapshots — the shared contract dir must not grow unboundedly, and the
# tee's own sweep matches *.json only.
find "$CTX_DIR" -maxdepth 1 -name '*.compacted' -mmin +20160 -exec rm -f {} + 2>/dev/null || true

# Compaction opens a fresh window: re-arm the blocking gate's grace budget.
STATE_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/context-guard}/state"
rm -f "$STATE_DIR/$SESSION.gate-count" 2>/dev/null || true

hook::emit_telemetry "post-compact-mark" "PostCompact" "ok" "$START_EPOCH" \
  '{"trigger":"'"$TRIGGER"'"}'
exit 0
