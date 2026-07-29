#!/usr/bin/env bash
# Contract test for post-compact-mark.sh (PostCompact, side-effect-only).
#
# Contract: writes the evidence-degraded marker
# ~/.claude/context-guard/context/<sid>.compacted with compacted_at (strict
# ISO-8601 UTC), trigger (manual|auto|unknown), and hook_event_name; resets
# the blocking gate's grace counter; fails open (no write, exit 0) on a
# missing/hostile session id or missing HOME; kill switch honored. Exit 0
# always.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/post-compact-mark.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

H="$WORK/home"
D="$WORK/data"
MARK="$H/.claude/context-guard/context"

run() { # <payload> [extra env k=v...]
  local payload="$1"
  shift
  printf '%s' "$payload" | HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="" env "$@" bash "$HOOK" 2>/dev/null
}

# 1. Auto trigger recorded.
run '{"session_id":"s1","hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
if [[ $RC -eq 0 && -f "$MARK/s1.compacted" ]]; then ok "marker written (auto)"; else fail "marker missing: rc=$RC"; fi
if grep -q '"trigger":"auto"' "$MARK/s1.compacted" 2>/dev/null; then ok "trigger=auto recorded"; else fail "trigger not recorded"; fi
if grep -Eq '"compacted_at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$MARK/s1.compacted"; then
  ok "compacted_at is strict ISO-8601 UTC"
else
  fail "compacted_at malformed: $(cat "$MARK/s1.compacted" 2>/dev/null)"
fi
if command -v jq >/dev/null 2>&1; then
  if jq -e . "$MARK/s1.compacted" >/dev/null 2>&1; then ok "marker is valid JSON"; else fail "marker JSON invalid"; fi
fi

# 2. Manual trigger recorded; marker is last-write-wins.
run '{"session_id":"s1","hook_event_name":"PostCompact","trigger":"manual"}'
if grep -q '"trigger":"manual"' "$MARK/s1.compacted" 2>/dev/null; then ok "manual overwrite (last-write-wins)"; else fail "manual overwrite failed"; fi

# 3. Unrecognized trigger degrades to unknown.
run '{"session_id":"s2","hook_event_name":"PostCompact","trigger":"weird"}'
if grep -q '"trigger":"unknown"' "$MARK/s2.compacted" 2>/dev/null; then ok "unrecognized trigger → unknown"; else fail "trigger sanitization failed"; fi

# 4. Grace counter reset.
mkdir -p "$D/state"
printf '9\n' >"$D/state/s3.gate-count"
run '{"session_id":"s3","hook_event_name":"PostCompact","trigger":"auto"}'
if [[ ! -e "$D/state/s3.gate-count" ]]; then ok "gate grace counter reset on compact"; else fail "grace counter not reset"; fi

# 5. Missing session id → no write, exit 0.
before=$(find "$MARK" -name '*.compacted' 2>/dev/null | wc -l)
run '{"hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
after=$(find "$MARK" -name '*.compacted' 2>/dev/null | wc -l)
if [[ $RC -eq 0 && "$before" == "$after" ]]; then ok "missing session id fails open"; else fail "missing sid: rc=$RC"; fi

# 6. Hostile session id → no write outside the contract dir, exit 0.
run '{"session_id":"../../evil","hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
if [[ $RC -eq 0 && ! -e "$H/.claude/evil.compacted" && ! -e "$H/.claude/context-guard/evil.compacted" ]]; then
  ok "hostile session id fails open (no traversal)"
else
  fail "hostile sid: rc=$RC"
fi

# 7. Kill switch honored.
run '{"session_id":"s4","hook_event_name":"PostCompact","trigger":"auto"}' CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED=false
RC=$?
if [[ $RC -eq 0 && ! -e "$MARK/s4.compacted" ]]; then ok "kill switch suppresses the marker"; else fail "kill switch: rc=$RC"; fi

# 8. Empty stdin → no write, exit 0.
run ''
RC=$?
if [[ $RC -eq 0 ]]; then ok "empty stdin fails open"; else fail "empty stdin: rc=$RC"; fi

# 9. Large payload (real PostCompact carries the full compact_summary):
# marker must still be written. Guards the Win32-pipe single-read timeout
# regression measured at ~80KB.
BIG=$(printf 'x%.0s' $(seq 1 150000))
run "{\"session_id\":\"sbig\",\"hook_event_name\":\"PostCompact\",\"trigger\":\"auto\",\"compact_summary\":\"$BIG\"}"
RC=$?
if [[ $RC -eq 0 && -f "$MARK/sbig.compacted" ]]; then ok "marker written for a 150KB payload"; else fail "large payload: rc=$RC marker=$([[ -f "$MARK/sbig.compacted" ]] && echo yes || echo no)"; fi

# 10. Old sibling markers are pruned on write (14-day cutoff, mirroring the
# tee's snapshot sweep) so the shared contract dir cannot grow unboundedly.
printf '{"compacted_at":"2020-01-01T00:00:00Z","trigger":"auto"}
' >"$MARK/sold.compacted"
if command -v touch >/dev/null 2>&1; then
  touch -d '30 days ago' "$MARK/sold.compacted" 2>/dev/null || touch -t 202001010000 "$MARK/sold.compacted" 2>/dev/null || true
fi
run '{"session_id":"sprune","hook_event_name":"PostCompact","trigger":"auto"}'
if [[ ! -e "$MARK/sold.compacted" && -f "$MARK/sprune.compacted" ]]; then
  ok "stale markers pruned on write (14-day cutoff)"
else
  fail "stale marker not pruned"
fi

# 11. Marker persist failure (temp-file write blocked by a read-only
# directory) must still exit 0 (SIDE-EFFECT-ONLY: PostCompact has no
# decision control) but report telemetry status=error rather than "ok" —
# operators must not be told a marker was recorded when consumers will never
# see it. A directory-mode block (not a directory-at-the-target-path: mv
# onto an existing directory moves INTO it rather than failing) is the
# standard POSIX way to force this, but is a documented no-op on filesystems
# without enforced POSIX modes (e.g. Windows ACL volumes under Git Bash —
# reader-contract.md's own caveat). Probe the restriction actually took
# effect before asserting on it; skip honestly rather than false-failing on
# such a filesystem.
make_sink() {
  local s
  s="$(mktemp "$WORK/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >%q\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}
wait_for_sink() {
  local f="$1" tries=150
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

chmod 555 "$MARK"
probe_blocked=1
: >"$MARK/.write-probe" 2>/dev/null && probe_blocked=0
rm -f "$MARK/.write-probe" 2>/dev/null
if ((probe_blocked)); then
  TEL="$WORK/tel-fail.json"
  SINK="$(make_sink "$TEL")"
  printf '{"session_id":"sfail","hook_event_name":"PostCompact","trigger":"auto"}' |
    HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" >/dev/null 2>&1
  RC=$?
  chmod 755 "$MARK"
  if [[ $RC -eq 0 ]]; then ok "marker persist failure still exits 0"; else fail "marker persist failure: rc=$RC"; fi
  if wait_for_sink "$TEL" && [[ "$(jq -r '.status' "$TEL" 2>/dev/null)" == "error" ]]; then
    ok "marker persist failure reports telemetry status=error"
  else
    fail "telemetry status not error: $(cat "$TEL" 2>/dev/null)"
  fi
else
  chmod 755 "$MARK"
  echo "SKIP: filesystem does not enforce directory write-mode (no POSIX ACL enforcement here) — cannot simulate a persist failure"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
