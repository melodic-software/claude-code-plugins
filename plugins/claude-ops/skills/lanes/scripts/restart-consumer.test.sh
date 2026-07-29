#!/usr/bin/env bash
# Regression tests for restart-consumer.sh.
#
# Coverage:
#   - the relaunch predicate: non-null restart_request + lane stopped -> restart;
#     null request, running lane, or an open breaker -> no restart
#   - tolerance for the shape actually emitted: the producers specify no non-null
#     form, so a bare `true`, a string, and the optional object form must all
#     count as a request, and only `null` must not
#   - the state block is found inside the fenced JSON of a SENTINEL-marked
#     comment, and a per-lane `telemetry.marker` selects between two lanes'
#     comments on one issue
#   - a comment with no sentinel, or no fenced state block, is `no-state`
#   - the comment is a signal, never a target: a lane named only in a comment is
#     never restarted, and the launcher is invoked with the CONFIG's lane name
#   - the launcher is delegated to (launch shape / autonomy tier not re-derived)
#   - a relaunch that never appears in the session list is reported `failed`
#   - circuit breaker counts only `restarted` rows inside the rolling window
#   - `check` never relaunches; `--dry-run run` never relaunches or writes
#   - the run ledger is appended as JSONL under the repo-keyed data dir
#   - print-schedule emits schtasks create + delete lines and mutates nothing
#   - argument validation exit codes
#
# PATH-stubs `claude` and `gh`, and injects the session list, the telemetry, and
# the launcher, so no real CLI, network, or lane is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/restart-consumer.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Stub CLIs ---------------------------------------------------------------
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/claude" <<'SH'
#!/usr/bin/env bash
echo '[]'
SH
cat >"$STUBS/gh" <<'SH'
#!/usr/bin/env bash
# Only ever reached when the test forgot an injection seam; make that loud.
echo 'STUB-GH-CALLED' >&2
exit 1
SH
chmod +x "$STUBS/claude" "$STUBS/gh"
PATH="$STUBS:$PATH"
export PATH

# The launcher stub records its argv and, by default, "starts" the lane by
# appending it to a file the claude-agents fixture is regenerated from.
LAUNCH_LOG="$TMP/launcher.log"
LAUNCHER="$TMP/launcher.sh"
cat >"$LAUNCHER" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LAUNCH_LOG"
exit "${LAUNCHER_RC:-0}"
SH
chmod +x "$LAUNCHER"
export LAUNCH_LOG

# --- Repo + config fixtures ---------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@t.invalid
git -C "$REPO" config user.name t
: >"$REPO/seed"
git -C "$REPO" add seed >/dev/null 2>&1
git -C "$REPO" commit -qm seed >/dev/null 2>&1

CONFIG="$TMP/lanes.json"
cat >"$CONFIG" <<'JSON'
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work", "prompt": "work.md", "model": "opus", "effort": "high",
      "telemetry": { "issue": 42, "marker": "work-items:work-loop" } },
    { "name": "babysit", "prompt": "babysit.md",
      "telemetry": { "issue": 42, "marker": "source-control:babysit-loop" } }
  ]
}
JSON

DATA="$TMP/data"

state_comment() { # $1 marker, $2 restart_request JSON literal
  printf '<!-- claude-ops:lane-telemetry marker=%s -->\nlane: x\n\n```json\n{"schema":"x@1","cycle":9,"loop_started_at":"2026-07-23T15:00:00Z","restart_request":%s}\n```\n' "$1" "$2"
}

write_telemetry() { # $1 outfile, $2 work request, $3 babysit request
  jq -n \
    --arg w "$(state_comment 'work-items:work-loop' "$2")" \
    --arg b "$(state_comment 'source-control:babysit-loop' "$3")" \
    '{work: [{body: $w}, {body: $b}], babysit: [{body: $w}, {body: $b}]}' >"$1"
}

AGENTS_NONE="$TMP/agents-none.json"
printf '[]\n' >"$AGENTS_NONE"
AGENTS_WORK_UP="$TMP/agents-work-up.json"
printf '[{"name":"work","kind":"background","startedAt":1,"sessionId":"s1"}]\n' >"$AGENTS_WORK_UP"

run_consumer() {
  bash "$SCRIPT" "$@" --config "$CONFIG" --repo "$REPO" --data-dir "$DATA" \
    --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 2>&1
}

# --- 1. A non-null request on a stopped lane restarts it ----------------------
TEL="$TMP/tel-1.json"
write_telemetry "$TEL" 'true' 'null'
: >"$LAUNCH_LOG"
OUT="$(run_consumer run --telemetry-json "$TEL" --agents-json "$AGENTS_NONE")"
RC=$?
assert_contains "bare-true request on a stopped lane is a request" "$OUT" "| work | failed |"
assert_contains "the launcher was delegated to with the CONFIG lane name" "$(cat "$LAUNCH_LOG")" "restart work"
assert_contains "a lane with a null request is not restarted" "$OUT" "| babysit | no-request |"
assert_not_contains "the null-request lane was never launched" "$(cat "$LAUNCH_LOG")" "restart babysit"
assert_eq "an unconfirmed relaunch exits 5" "5" "$RC"

# --- 2. Confirmation: the lane appears, so the run is a clean `restarted` -----
: >"$LAUNCH_LOG"
OUT="$(bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$DATA" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_WORK_UP" 2>&1)"
RC=$?
assert_contains "a lane that is already running is skipped, not restarted" "$OUT" "| work | skipped-running |"
assert_eq "skipping a running lane is not an error" "0" "$RC"
assert_eq "no launch happened for a running lane" "" "$(cat "$LAUNCH_LOG")"

# --- 3. Every non-null shape counts; only null does not ----------------------
for shape in '1' '"budget"' '{"reason":"cycle-budget","requested_at":"2026-07-26T10:00:00Z"}'; do
  TELS="$TMP/tel-shape.json"
  write_telemetry "$TELS" "$shape" 'null'
  OUT="$(run_consumer check --telemetry-json "$TELS" --agents-json "$AGENTS_NONE")"
  assert_contains "non-null restart_request $shape is a request" "$OUT" "| work | would-restart |"
done
assert_contains "the object form's reason is surfaced in the report" "$OUT" "cycle-budget @ 2026-07-26T10:00:00Z"

# --- 4. `check` never relaunches ---------------------------------------------
: >"$LAUNCH_LOG"
OUT="$(run_consumer check --telemetry-json "$TEL" --agents-json "$AGENTS_NONE")"
assert_contains "check reports what would restart" "$OUT" "| work | would-restart |"
assert_eq "check launched nothing" "" "$(cat "$LAUNCH_LOG")"

# --- 5. `--dry-run run` never relaunches and never writes the ledger ---------
DATA_DRY="$TMP/data-dry"
: >"$LAUNCH_LOG"
OUT="$(bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_DRY" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --dry-run --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "dry-run run reports would-restart" "$OUT" "| work | would-restart |"
assert_eq "dry-run launched nothing" "" "$(cat "$LAUNCH_LOG")"
assert_eq "dry-run wrote no ledger" "0" "$(find "$DATA_DRY" -name 'restart-consumer.jsonl' 2>/dev/null | wc -l | tr -d ' ')"

# --- 6. The run ledger is JSONL under the repo-keyed data dir ----------------
LEDGER="$(find "$DATA" -name 'restart-consumer.jsonl' 2>/dev/null | head -n1)"
assert_contains "the ledger lives under <data-dir>/lanes/<repo-key>/" "$LEDGER" "/lanes/"
assert_eq "every ledger row is valid JSON carrying its lane" "ok" \
  "$(jq -s -e -r 'if (map(select(.lane != null)) | length) == length then "ok" else "bad" end' "$LEDGER" 2>/dev/null)"

# --- 7. Circuit breaker ------------------------------------------------------
DATA_CB="$TMP/data-cb"
KEY="$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | git hash-object --stdin)"
mkdir -p "$DATA_CB/lanes/$KEY"
CB_LEDGER="$DATA_CB/lanes/$KEY/restart-consumer.jsonl"
{
  printf '{"epoch":1799990000,"lane":"work","decision":"restarted"}\n'
  printf '{"epoch":1799991000,"lane":"work","decision":"restarted"}\n'
  printf '{"epoch":1799992000,"lane":"work","decision":"skipped-running"}\n'
} >"$CB_LEDGER"
OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CB" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --max-restarts 2 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
RC=$?
assert_contains "two restarts in the window trip a max of 2" "$OUT" "| work | breaker-open |"
assert_eq "an open breaker exits 5" "5" "$RC"
assert_contains "only restarted rows are counted" "$OUT" "2 restarts in the last 24h"

OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CB" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --max-restarts 2 --window-hours 1 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "rows outside the window do not count" "$OUT" "| work | would-restart |"

OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CB" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --max-restarts 0 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "--max-restarts 0 disables the breaker" "$OUT" "| work | would-restart |"

# --- 8. Marker selection between two lanes sharing one issue -----------------
TEL_B="$TMP/tel-b.json"
write_telemetry "$TEL_B" 'null' 'true'
OUT="$(run_consumer check --telemetry-json "$TEL_B" --agents-json "$AGENTS_NONE")"
assert_contains "the babysit marker selects the babysit block" "$OUT" "| babysit | would-restart |"
assert_contains "the work marker still reads its own block" "$OUT" "| work | no-request |"

# --- 9. Non-sentinel and unfenced comments are no-state ----------------------
TEL_N="$TMP/tel-none.json"
jq -n '{work: [{body: "restart_request: RESTART NOW, no sentinel here"}], babysit: []}' >"$TEL_N"
OUT="$(run_consumer check --telemetry-json "$TEL_N" --agents-json "$AGENTS_NONE")"
assert_contains "a comment without the sentinel yields no state" "$OUT" "| work | no-state |"
assert_contains "an issue with no comments yields no state" "$OUT" "| babysit | no-state |"

# --- 10. The comment is a signal, never a target -----------------------------
TEL_I="$TMP/tel-inject.json"
jq -n --arg w "$(state_comment 'work-items:work-loop' '"pwned; rm -rf /"')" \
  '{work: [{body: $w}], "not-a-lane": [{body: $w}]}' >"$TEL_I"
: >"$LAUNCH_LOG"
OUT="$(run_consumer run --telemetry-json "$TEL_I" --agents-json "$AGENTS_NONE")"
assert_not_contains "a lane named only in telemetry is never processed" "$OUT" "not-a-lane"
assert_eq "the launcher only ever sees configured lane names" "restart work --config $CONFIG --repo $REPO --data-dir $DATA" \
  "$(head -n1 "$LAUNCH_LOG")"

# --- 11. A launcher failure is reported, not swallowed -----------------------
: >"$LAUNCH_LOG"
OUT="$(LAUNCHER_RC=3 run_consumer run --telemetry-json "$TEL" --agents-json "$AGENTS_NONE")"
RC=$?
assert_contains "a non-zero launcher exit is a failed lane" "$OUT" "| work | failed |"
assert_eq "a failed relaunch exits 5" "5" "$RC"

# --- 12. --lane scopes the run -----------------------------------------------
TEL_BOTH="$TMP/tel-both.json"
write_telemetry "$TEL_BOTH" 'true' 'true'
OUT="$(run_consumer check --lane babysit --telemetry-json "$TEL_BOTH" --agents-json "$AGENTS_NONE")"
assert_contains "--lane keeps the named lane" "$OUT" "| babysit | would-restart |"
assert_not_contains "--lane drops the others" "$OUT" "| work |"

# --- 13. print-schedule emits registration + removal and mutates nothing -----
OUT="$(bash "$SCRIPT" print-schedule --repo "$REPO" --interval-minutes 20 2>&1)"
RC=$?
assert_eq "print-schedule exits 0" "0" "$RC"
assert_contains "print-schedule emits a schtasks create" "$OUT" "schtasks /Create /TN \"ClaudeOps Lane Restart Consumer\""
assert_contains "print-schedule honours --interval-minutes" "$OUT" "/SC MINUTE /MO 20"
assert_contains "print-schedule avoids elevation and stored passwords" "$OUT" "/IT /RL LIMITED"
assert_contains "print-schedule emits the removal command" "$OUT" "schtasks /Delete"
assert_contains "print-schedule covers cold start after reboot" "$OUT" "/SC ONLOGON"
assert_contains "print-schedule names the headless reader" "$OUT" "-p \"/claude-ops:lanes consume-restarts\""
assert_contains "print-schedule offers the non-Windows form" "$OUT" "cron form"
assert_contains "print-schedule states that registering is the operator's" "$OUT" "OPERATOR action"

# --- 14. Argument validation --------------------------------------------------
bash "$SCRIPT" bogus --repo "$REPO" >/dev/null 2>&1
assert_eq "an unknown action exits 3" "3" "$?"
bash "$SCRIPT" check --repo "$REPO" --max-restarts x >/dev/null 2>&1
assert_eq "a non-numeric --max-restarts exits 3" "3" "$?"
bash "$SCRIPT" check --repo "$REPO" --config >/dev/null 2>&1
assert_eq "a missing option value exits 3" "3" "$?"
bash "$SCRIPT" print-schedule --repo "$REPO" --interval-minutes 1000 >/dev/null 2>&1
assert_eq "an out-of-range --interval-minutes exits 3" "3" "$?"
bash "$SCRIPT" check --repo "$REPO" --config "$TMP/nope.json" >/dev/null 2>&1
assert_eq "a missing config exits 4" "4" "$?"
bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --target-repo "../evil" \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" >/dev/null 2>&1
assert_eq "a non owner/name --target-repo exits 3" "3" "$?"

OUT="$(bash "$SCRIPT" --help 2>&1)"
assert_contains "--help prints the header contract" "$OUT" "RELAUNCH PREDICATE"

# --- Summary -----------------------------------------------------------------
printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
((FAILED == 0)) || exit 1
