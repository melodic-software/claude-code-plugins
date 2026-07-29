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
#   - circuit breaker counts relaunch ATTEMPTS (`restarted` and `failed`, never
#     the pre-launch `error` / `api-error` reads) inside the rolling window, and
#     FAILS CLOSED (budget reported spent) on a ledger that does not parse
#   - `check` never relaunches; `check` and `--dry-run run` never write the ledger
#   - the run ledger is appended as JSONL under the repo-keyed data dir, carries
#     only incident decisions, and never the routine per-tick ones
#   - a `run` holds a cross-process lock: a second concurrent run skips cleanly
#     (exit 0, `lock-held`), relaunches nothing, and the lock is released on exit
#   - a telemetry read that ERRORS is `api-error`, never `no-state`
#   - the consumer's own telemetry upsert: pinned issue, the morning-brief search
#     hit, the exact-title fallback, and the no-issue-found warn + ledger-only
#   - the morning-brief issue-discovery literals are byte-identical in both files
#   - print-schedule emits schtasks create + delete lines and mutates nothing,
#     and substitutes a passed --data-dir into the offline form
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
# The gh stub is loud-by-default: reaching it means a test forgot an injection
# seam. Setting GH_LOG opts a case in to argv recording and canned responses —
# the only way to exercise the telemetry upsert, whose gh calls (and the sibling
# telemetry-upsert.sh's) have no injection seam of their own.
cat >"$STUBS/gh" <<'SH'
#!/usr/bin/env bash
if [[ -z "${GH_LOG:-}" ]]; then
  echo 'STUB-GH-CALLED' >&2
  exit 1
fi
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
*"/comments"*)
  [[ -n "${GH_FAIL_COMMENTS:-}" ]] && exit 1
  case "$*" in
  *"--method POST"* | *"--method PATCH"*) printf '{"id":999,"html_url":"https://example.invalid/c/999"}\n' ;;
  *) printf '[]\n' ;;
  esac
  ;;
*"loop-lane telemetry running per-lane status in:title"*) printf '%s\n' "${GH_SEARCH_RESULT:-[]}" ;;
*"Lane telemetry in:title"*) printf '%s\n' "${GH_TITLE_RESULT:-[]}" ;;
"api user"*) printf 'stub-user\n' ;;
*) printf '[]\n' ;;
esac
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
  # shellcheck disable=SC2016  # backticks are the literal markdown fence of the telemetry fixture
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
assert_contains "routine ticks do not count toward the breaker" "$OUT" "2 relaunch attempts in the last 24h"

# The breaker bounds ATTEMPTS, not successes: a relaunch that failed or never
# came up must spend budget, or a lane that can never start retries forever.
DATA_CB_F="$TMP/data-cb-failed"
mkdir -p "$DATA_CB_F/lanes/$KEY"
{
  printf '{"epoch":1799990000,"lane":"work","decision":"restarted"}\n'
  printf '{"epoch":1799991000,"lane":"work","decision":"failed"}\n'
} >"$DATA_CB_F/lanes/$KEY/restart-consumer.jsonl"
OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CB_F" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --max-restarts 2 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "a failed relaunch spends breaker budget" "$OUT" "| work | breaker-open |"
assert_contains "the failed row is counted as an attempt" "$OUT" "2 relaunch attempts in the last 24h"

# Read failures precede any launch, so a transient forge outage must not spend a
# lane's restart budget.
DATA_CB_E="$TMP/data-cb-error"
mkdir -p "$DATA_CB_E/lanes/$KEY"
{
  printf '{"epoch":1799990000,"lane":"work","decision":"api-error"}\n'
  printf '{"epoch":1799991000,"lane":"work","decision":"error"}\n'
} >"$DATA_CB_E/lanes/$KEY/restart-consumer.jsonl"
OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CB_E" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --max-restarts 2 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "read failures never spend breaker budget" "$OUT" "| work | would-restart |"

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
assert_contains "print-schedule names the headless reader" "$OUT" "-p \"/claude-ops:lanes consume-restarts run\""
assert_not_contains "the scheduled command never defaults to read-only check" "$OUT" "consume-restarts\" --output-format"
assert_contains "print-schedule offers the non-Windows form" "$OUT" "cron form"
assert_contains "print-schedule states that registering is the operator's" "$OUT" "OPERATOR action"

# --- 14. Argument validation --------------------------------------------------
bash "$SCRIPT" bogus --repo "$REPO" >/dev/null 2>&1
assert_eq "an unknown action exits 3" "3" "$?"
# --max-restarts 0 isolates argument parsing from the shared ledger: earlier
# sections leave `failed` rows in it, and those now spend breaker budget.
OUT="$(run_consumer consume-restarts check --max-restarts 0 --telemetry-json "$TEL" --agents-json "$AGENTS_NONE")"
assert_eq "a leading consume-restarts skill token is accepted" "0" "$?"
assert_contains "the token after consume-restarts is the action" "$OUT" "restart-consumer: check"
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

# --- 15. The ledger records incidents, not routine ticks ---------------------
DATA_LG="$TMP/data-ledger"
LG_KEY="$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | git hash-object --stdin)"
LG_LEDGER="$DATA_LG/lanes/$LG_KEY/restart-consumer.jsonl"
: >"$LAUNCH_LOG"
bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_LG" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_WORK_UP" >/dev/null 2>&1
assert_eq "a run of only routine decisions writes no ledger at all" "0" \
  "$(find "$DATA_LG" -name 'restart-consumer.jsonl' 2>/dev/null | wc -l | tr -d ' ')"

bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_LG" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" >/dev/null 2>&1
assert_eq "an incident decision IS ledgered" "1" \
  "$(jq -s -r 'length' "$LG_LEDGER" 2>/dev/null)"
assert_eq "the routine no-request tick of the same run is not" "failed" \
  "$(jq -s -r '.[0].decision' "$LG_LEDGER" 2>/dev/null)"

# `check` is documented read-only; a ledger row from a check is precisely what
# would make the doc's Verify step pass on a check-only schedule.
DATA_CHK="$TMP/data-check"
bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_CHK" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" >/dev/null 2>&1
assert_eq "check writes no ledger (it is documented read-only)" "0" \
  "$(find "$DATA_CHK" -name 'restart-consumer.jsonl' 2>/dev/null | wc -l | tr -d ' ')"

# --- 16. The circuit breaker fails CLOSED on a ledger that does not parse -----
DATA_TORN="$TMP/data-torn"
mkdir -p "$DATA_TORN/lanes/$LG_KEY"
{
  printf '{"epoch":1799990000,"lane":"work","decision":"restarted"}\n'
  printf '{"epoch":1799991000,"lane":"work","dec\n'
} >"$DATA_TORN/lanes/$LG_KEY/restart-consumer.jsonl"
OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$DATA_TORN" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
RC=$?
assert_contains "a torn ledger line trips the breaker rather than clearing it" "$OUT" "| work | breaker-open |"
assert_contains "the corrupt ledger is named in a warning" "$OUT" "run ledger did not parse"
assert_eq "failing closed still exits 5" "5" "$RC"

# --- 17. A `run` holds a cross-process lock across the relaunch span ----------
# The launcher stub is the concurrency probe: it fires while the outer run holds
# the lock and is mid-relaunch, which is exactly the window two schtasks tasks
# firing at logon would collide in.
LOCK_PROBE="$TMP/lock-probe.out"
LOCK_LAUNCHER="$TMP/launcher-lock.sh"
cat >"$LOCK_LAUNCHER" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"\$LAUNCH_LOG"
bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-lock" \\
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \\
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" >"$LOCK_PROBE" 2>&1
printf 'inner-rc=%s\n' "\$?" >>"$LOCK_PROBE"
exit 0
SH
chmod +x "$LOCK_LAUNCHER"
: >"$LAUNCH_LOG"
OUT="$(bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-lock" \
  --target-repo "owner/name" --launcher "$LOCK_LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "a concurrent run skips instead of relaunching" "$(cat "$LOCK_PROBE")" "| (none) | lock-held |"
assert_contains "the locked-out run exits 0 (a skipped tick is not a failure)" "$(cat "$LOCK_PROBE")" "inner-rc=0"
assert_not_contains "the locked-out run never reached a lane decision" "$(cat "$LOCK_PROBE")" "| work |"
assert_eq "only the lock holder ever invoked the launcher" "1" "$(grep -c 'restart work' "$LAUNCH_LOG")"
assert_contains "the lock holder itself proceeded normally" "$OUT" "| work |"
assert_eq "the lock is released when the run exits" "0" \
  "$(find "$TMP/data-lock" -name '.restart-consumer-lock' -type d 2>/dev/null | wc -l | tr -d ' ')"

# A lock old enough that no live run can still hold it is reclaimed, so a
# hard-killed run cannot wedge an unattended schedule forever.
LOCK_STALE="$TMP/data-lock-stale/lanes/$LG_KEY/.restart-consumer-lock"
mkdir -p "$LOCK_STALE"
printf '1799990000\n' >"$LOCK_STALE/acquired-at"
: >"$LAUNCH_LOG"
OUT="$(bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-lock-stale" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "an abandoned lock is reclaimed, not honoured forever" "$OUT" "reclaiming a lock held since epoch"
assert_contains "the reclaiming run then does its work" "$OUT" "| work | failed |"

# A lock with no stamp yet is NOT stolen — the holder may have won the mkdir
# microseconds ago. It is stamped instead, so it can age out on a later tick.
LOCK_FRESH="$TMP/data-lock-fresh/lanes/$LG_KEY/.restart-consumer-lock"
mkdir -p "$LOCK_FRESH"
: >"$LAUNCH_LOG"
OUT="$(bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-lock-fresh" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "an unstamped lock is respected, never stolen" "$OUT" "| (none) | lock-held |"
assert_eq "the unstamped lock is dated so it can age out later" "1800000000" \
  "$(tr -d '\r\n' <"$LOCK_FRESH/acquired-at" 2>/dev/null)"
assert_eq "nothing was launched while locked out" "" "$(cat "$LAUNCH_LOG")"

# `check` mutates nothing, so it never contends for the lock.
OUT="$(bash "$SCRIPT" check --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-lock-fresh" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --telemetry-json "$TEL" --agents-json "$AGENTS_NONE" 2>&1)"
assert_contains "check runs regardless of a held lock" "$OUT" "| work | would-restart |"

# --- 18. A failed telemetry READ is api-error, never no-state ----------------
# no-state means "the lane did not ask"; a gh blip must never wear that face.
OUT="$(GH_LOG="$TMP/gh-apierr.log" GH_FAIL_COMMENTS=1 bash "$SCRIPT" check \
  --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-apierr" \
  --target-repo "owner/name" --launcher "$LAUNCHER" --no-telemetry --now 1800000000 \
  --agents-json "$AGENTS_NONE" 2>&1)"
RC=$?
assert_contains "a failed comment read is its own decision" "$OUT" "| work | api-error |"
assert_not_contains "a failed comment read is never reported as no-state" "$OUT" "| work | no-state |"
assert_eq "an unreadable lane state exits 5" "5" "$RC"

# --- 19. The consumer's own telemetry upsert ---------------------------------
# All four issue-resolution paths of upsert_own_telemetry, which every case above
# suppresses with --no-telemetry.
run_telemetry() { # $@ extra args; GH_LOG/GH_* set by the caller
  bash "$SCRIPT" run --config "$CONFIG" --repo "$REPO" --data-dir "$TMP/data-tel" \
    --target-repo "owner/name" --launcher "$LAUNCHER" --now 1800000000 \
    --telemetry-json "$TEL" --agents-json "$AGENTS_WORK_UP" "$@" 2>&1
}

GH_PINNED="$TMP/gh-pinned.log"
OUT="$(GH_LOG="$GH_PINNED" run_telemetry --telemetry-issue 77)"
assert_contains "a pinned --telemetry-issue is used verbatim" "$(cat "$GH_PINNED")" "issues/77/comments"
assert_not_contains "a pinned issue skips discovery entirely" "$(cat "$GH_PINNED")" "in:title"
assert_contains "the upserted body carries the morning-brief header fields" "$(cat "$GH_PINNED")" "last-cycle: 2027-01-15T08:00:00Z"
assert_contains "the upsert is marker-identified for edit-in-place" "$(cat "$GH_PINNED")" "claude-ops:restart-consumer"

GH_SEARCH="$TMP/gh-search.log"
OUT="$(GH_LOG="$GH_SEARCH" GH_SEARCH_RESULT='[{"number":55},{"number":91}]' run_telemetry)"
assert_contains "unpinned discovery reuses the morning brief's own title search" "$(cat "$GH_SEARCH")" \
  "loop-lane telemetry running per-lane status in:title"
assert_contains "the search hit selects the lowest-numbered issue" "$(cat "$GH_SEARCH")" "issues/55/comments"

GH_FB="$TMP/gh-fallback.log"
OUT="$(GH_LOG="$GH_FB" GH_SEARCH_RESULT='[]' \
  GH_TITLE_RESULT='[{"number":63,"title":"Lane telemetry: restart-consumer"},{"number":64,"title":"Lane telemetry: work"}]' \
  run_telemetry)"
assert_contains "an empty search falls back to the exact-title lookup" "$(cat "$GH_FB")" "Lane telemetry in:title"
assert_contains "the fallback matches the title EXACTLY, not fuzzily" "$(cat "$GH_FB")" "issues/63/comments"

GH_NONE="$TMP/gh-none.log"
OUT="$(GH_LOG="$GH_NONE" GH_SEARCH_RESULT='[]' GH_TITLE_RESULT='[]' run_telemetry)"
assert_contains "no resolvable issue degrades loudly, naming the fix" "$OUT" "Pass --telemetry-issue N"
assert_not_contains "no resolvable issue means no comment is written anywhere" "$(cat "$GH_NONE")" "--method POST"
assert_contains "the run itself is unaffected by a missing telemetry issue" "$OUT" "| work | skipped-running |"

# --- 20. The morning-brief discovery literals are verbatim in both files -----
# Not refactored to a shared source: the two skills are independently
# installable. This gate is what makes the duplication safe — if the reader's
# search changes, the consumer would silently post where the brief never looks.
BRIEF="$SCRIPT_DIR/../../morning-brief/scripts/morning-brief.sh"
for literal in 'loop-lane telemetry running per-lane status in:title' 'sort_by(.number) | .[0].number // empty'; do
  assert_contains "the consumer carries the discovery literal [$literal]" "$(cat "$SCRIPT")" "$literal"
  assert_contains "the morning brief carries the SAME literal [$literal]" "$(cat "$BRIEF")" "$literal"
done

# --- 21. print-schedule makes the offline form copy-pasteable ----------------
OUT="$(bash "$SCRIPT" print-schedule --repo "$REPO" --data-dir "$DATA" 2>&1)"
assert_contains "a passed --data-dir is substituted into the offline form" "$OUT" "--data-dir '$DATA'"
OUT="$(bash "$SCRIPT" print-schedule --repo "$REPO" 2>&1)"
assert_contains "without one, the placeholder still says what to substitute" "$OUT" "<the CLAUDE_PLUGIN_DATA dir skill runs use>"

# --- Summary -----------------------------------------------------------------
printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
((FAILED == 0)) || exit 1
