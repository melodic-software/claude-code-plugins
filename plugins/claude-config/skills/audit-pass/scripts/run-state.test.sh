#!/usr/bin/env bash
# Regression tests for run-state.sh (self-contained — ships with the plugin).
#
# Three of these are NEGATIVE tests in the sense this repo means it: they mutate
# a copy of the script to delete exactly one check, and assert the mutated copy
# reaches the outcome the real one refuses. A test that would still pass with the
# check deleted proves nothing, and this plugin has already shipped that mistake.
#
# No jq, no git commits: `git init` plus `git remote add` is all lib/state-key.sh
# reads, so no signing configuration can make these error in setup.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/run-state.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_file() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "no such file: $2"; fi
}

# Every invocation runs with CLAUDE_PLUGIN_ROOT pinned, so a copy of the script
# placed outside the plugin tree still resolves lib/state-key.sh.
run() {
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" "$@"
}
run_copy() {
  local copy="$1"
  shift
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$copy" "$@"
}

DATA="$TEST_TMPDIR/plugin-data"
mkdir -p "$DATA"

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init --quiet >/dev/null 2>&1
git -C "$REPO" remote add origin https://github.com/example/demo.git >/dev/null 2>&1

# --- Case 1: paths ----------------------------------------------------------

OUT=$(run paths --plugin-data "$DATA" --run-id run-0001 --root "$REPO" 2>&1)
rc=$?
assert_exit "paths exits 0 on a git target" 0 "$rc"
assert_contains "paths echoes the plugin data dir it was given" "$OUT" "plugin_data=$DATA"
assert_contains "paths derives a state key through lib/state-key.sh" "$OUT" \
  "state_key=github.com/example/demo/"
assert_contains "the run dir is keyed under runs/<state-key>/<run-id>" "$OUT" \
  "run_dir=$DATA/runs/github.com/example/demo/"
assert_contains "the run dir ends in the run id" "$OUT" "/run-0001"

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" paths --run-id run-0001 2>&1) || rc=$?
assert_exit "paths exits 2 with no --plugin-data and no exported placeholder" 2 "$rc"
assert_contains "the refusal names why the placeholder is unavailable in Bash" "$OUT" \
  "not exported to the Bash tool"

rc=0
OUT=$(run paths --plugin-data "relative/dir" --run-id run-0001 2>&1) || rc=$?
assert_exit "a relative --plugin-data is refused" 2 "$rc"

# --- Case 2: run-id validation, the path-safety control ---------------------
#
# A run id becomes a directory component of a path assembled under the plugin's
# own data directory. lib/state-key.sh documents the traversal it defends its
# half against; this is the other half of the same door.

rc=0
OUT=$(run paths --plugin-data "$DATA" --run-id "a..b" --root "$REPO" 2>&1) || rc=$?
assert_exit "a run id containing '..' is refused" 2 "$rc"
assert_contains "the refusal names the traversal" "$OUT" "must not contain '..'"

rc=0
OUT=$(run paths --plugin-data "$DATA" --run-id "/etc/passwd" --root "$REPO" 2>&1) || rc=$?
assert_exit "a run id that is not a plain segment is refused" 2 "$rc"

rc=0
OUT=$(run paths --plugin-data "$DATA" --run-id "" --root "$REPO" 2>&1) || rc=$?
assert_exit "an empty run id is refused" 2 "$rc"

# 2a: NEGATIVE — delete the '..' arm and the traversal must get through.
BROKEN_DOTS="$TEST_TMPDIR/broken-dots.sh"
sed "/must not contain/s/.*/  *) : ;;/" "$SCRIPT" >"$BROKEN_DOTS"
if grep -q "must not contain" "$BROKEN_DOTS"; then
  fail "negative traversal case could not be constructed" \
    "the sed target no longer matches run-state.sh — the '..' rejection is UNVERIFIED by this run"
else
  rc=0
  broken_out=$(run_copy "$BROKEN_DOTS" paths --plugin-data "$DATA" --run-id "a..b" --root "$REPO" 2>&1) || rc=$?
  assert_exit "without the '..' arm the same id is accepted — the check discriminates" 0 "$rc"
  assert_contains "and it would have assembled a traversing run dir" "$broken_out" "/a..b"
fi

# 2b: NEGATIVE — delete the segment-shape check and an absolute id gets through.
BROKEN_SEG="$TEST_TMPDIR/broken-seg.sh"
# shellcheck disable=SC2016  # single quotes are required: `$id` here is the
# literal source text being matched inside run-state.sh, not a variable to expand.
sed 's|^  if \[\[ ! "\$id" =~ .*$|  if false; then|' "$SCRIPT" >"$BROKEN_SEG"
if grep -q 'if false; then' "$BROKEN_SEG"; then
  rc=0
  broken_out=$(run_copy "$BROKEN_SEG" paths --plugin-data "$DATA" --run-id "/etc/passwd" --root "$REPO" 2>&1) || rc=$?
  assert_exit "without the segment check an absolute id is accepted — the check discriminates" 0 "$rc"
  assert_contains "and it would have escaped the plugin namespace" "$broken_out" "/etc/passwd"
else
  fail "negative segment-shape case could not be constructed" \
    "the sed target no longer matches run-state.sh — the segment check is UNVERIFIED by this run"
fi

# --- Case 3: the lease, acquire through classify ----------------------------

RUN_DIR="$DATA/runs/demo/run-0001"
LEASE_OUT=$(run lease acquire --run-dir "$RUN_DIR" --run-id run-0001 --plugin-data "$DATA" 2>&1)
assert_contains "acquire prints the lease path" "$LEASE_OUT" "$RUN_DIR/lease"
assert_file "acquire writes the lease" "$RUN_DIR/lease"
LEASE=$(cat "$RUN_DIR/lease")
assert_contains "the lease records its run id" "$LEASE" "run_id=run-0001"
assert_contains "the lease records an owner epoch" "$LEASE" "owner_epoch=1"
assert_contains "the lease records the staleness threshold its writer committed to" "$LEASE" \
  "stale_after_s=1800"
assert_contains "the lease records its skew grace" "$LEASE" "skew_grace_s=60"
assert_eq "a freshly acquired lease classifies live" "live" "$(run lease classify --run-dir "$RUN_DIR")"

# A threshold of 0 does not merely shorten the window, it inverts the mechanism:
# `delta >= 0` fires on the first classify, so the lease is born abandoned and
# `--resume` would adopt it out from under the run that just wrote it. §3 now
# documents `--stale-after` as an operator lever, so its zero value has to refuse
# rather than quietly produce a lease no run could keep.
rc=0
OUT=$(run lease acquire --run-dir "$DATA/runs/demo/zero" --run-id zero --stale-after 0 --plugin-data "$DATA" 2>&1) || rc=$?
assert_exit "--stale-after 0 is refused rather than writing a lease born abandoned" 2 "$rc"
assert_contains "the refusal says what 0 would do" "$OUT" "classify stale the moment it is written"
rc=0
run lease acquire --run-dir "$DATA/runs/demo/zeroe" --run-id zeroe --epoch 0 --plugin-data "$DATA" >/dev/null 2>&1 || rc=$?
assert_exit "--epoch 0 is refused" 2 "$rc"
# Zero forward tolerance is a coherent choice and inverts nothing, so it stays legal.
rc=0
run lease acquire --run-dir "$DATA/runs/demo/zerosk" --run-id zerosk --skew-grace 0 --plugin-data "$DATA" >/dev/null 2>&1 || rc=$?
assert_exit "--skew-grace 0 stays legal" 0 "$rc"
assert_eq "and that lease is live when it is written" \
  "live" "$(run lease classify --run-dir "$DATA/runs/demo/zerosk")"

assert_eq "classify on a directory with no lease says missing, and does not error" \
  "missing" "$(run lease classify --run-dir "$DATA/runs/demo/absent" 2>/dev/null)"
rc=0
run lease classify --run-dir "$DATA/runs/demo/absent" >/dev/null 2>&1 || rc=$?
assert_exit "a missing lease is a classification, not a failure" 0 "$rc"

# A backdated heartbeat past the recorded threshold is stale.
STALE_DIR="$DATA/runs/demo/run-stale"
run lease acquire --run-dir "$STALE_DIR" --run-id run-stale --stale-after 30 --plugin-data "$DATA" >/dev/null 2>&1
NOW=$(date -u +%s)
{
  printf 'run_id=run-stale\npid=1\nstate=active\nowner_epoch=1\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW - 600))"
  printf 'stale_after_s=30\nskew_grace_s=60\n'
} >"$STALE_DIR/lease"
assert_eq "a heartbeat older than the recorded threshold classifies stale" \
  "stale" "$(run lease classify --run-dir "$STALE_DIR")"

# The threshold is read from the lease, not assumed by the classifier.
{
  printf 'run_id=run-stale\npid=1\nstate=active\nowner_epoch=1\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW - 600))"
  printf 'stale_after_s=100000\nskew_grace_s=60\n'
} >"$STALE_DIR/lease"
assert_eq "the same heartbeat under a longer recorded threshold classifies live" \
  "live" "$(run lease classify --run-dir "$STALE_DIR")"

# --- Case 4: the two-sided window's LOWER bound -----------------------------
#
# A forward clock jump writes a heartbeat into the future. Tested only as
# `now - heartbeat < stale_after`, that lease reads live for the whole skew
# interval even after the process is gone, so every --resume refuses an
# abandoned run indefinitely — the failure that costs the artifact rather than a
# re-run. This is assertion 3.9.

SKEW_DIR="$DATA/runs/demo/run-skew"
mkdir -p "$SKEW_DIR"
{
  printf 'run_id=run-skew\npid=1\nstate=active\nowner_epoch=1\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW + 7200))"
  printf 'stale_after_s=1800\nskew_grace_s=60\n'
} >"$SKEW_DIR/lease"
assert_eq "a heartbeat beyond the skew grace classifies stale, not live" \
  "stale" "$(run lease classify --run-dir "$SKEW_DIR" 2>/dev/null)"
assert_contains "and the skew is reported rather than swallowed" \
  "$(run lease classify --run-dir "$SKEW_DIR" 2>&1 >/dev/null)" "in the future"

# A small forward offset inside the grace is ordinary scheduling, not skew.
{
  printf 'run_id=run-skew\npid=1\nstate=active\nowner_epoch=1\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW + 5))"
  printf 'stale_after_s=1800\nskew_grace_s=60\n'
} >"$SKEW_DIR/lease"
assert_eq "a heartbeat within the skew grace still classifies live" \
  "live" "$(run lease classify --run-dir "$SKEW_DIR")"

# 4a: NEGATIVE — delete the lower bound and the future heartbeat reads live.
BROKEN_SKEW="$TEST_TMPDIR/broken-skew.sh"
# shellcheck disable=SC2016  # single quotes are required: the $((...)) here is the
# literal source text being matched in run-state.sh, not an expression to evaluate.
sed '/-lt \$((-skew_grace))/s/.*/  if false; then/' "$SCRIPT" >"$BROKEN_SKEW"
if grep -q 'if false; then' "$BROKEN_SKEW"; then
  {
    printf 'run_id=run-skew\npid=1\nstate=active\nowner_epoch=1\n'
    printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW + 7200))"
    printf 'stale_after_s=1800\nskew_grace_s=60\n'
  } >"$SKEW_DIR/lease"
  assert_eq "without the lower bound a dead run pins itself live — the bound discriminates" \
    "live" "$(run_copy "$BROKEN_SKEW" lease classify --run-dir "$SKEW_DIR" 2>/dev/null)"
else
  fail "negative skew case could not be constructed" \
    "the sed target no longer matches run-state.sh — the lower bound is UNVERIFIED by this run"
fi

# --- Case 5: heartbeat and the released tombstone ---------------------------

HB_DIR="$DATA/runs/demo/run-hb"
run lease acquire --run-dir "$HB_DIR" --run-id run-hb --plugin-data "$DATA" >/dev/null 2>&1
{
  printf 'run_id=run-hb\npid=1\nstate=active\nowner_epoch=2\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$((NOW - 600))"
  printf 'stale_after_s=30\nskew_grace_s=60\n'
} >"$HB_DIR/lease"
assert_eq "the stale lease is stale before the refresh" "stale" "$(run lease classify --run-dir "$HB_DIR")"
run lease heartbeat --run-dir "$HB_DIR" >/dev/null 2>&1
assert_eq "a heartbeat refresh brings it back live" "live" "$(run lease classify --run-dir "$HB_DIR")"
assert_contains "the refresh preserves the owner epoch" "$(cat "$HB_DIR/lease")" "owner_epoch=2"

# max(now, previous): a rewound clock must not make a live run read stale, so a
# refresh never moves the heartbeat backwards.
FUTURE=$((NOW + 7200))
{
  printf 'run_id=run-hb\npid=1\nstate=active\nowner_epoch=2\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$FUTURE"
  printf 'stale_after_s=1800\nskew_grace_s=60\n'
} >"$HB_DIR/lease"
assert_eq "a refresh does not move heartbeat_at backwards" "$FUTURE" \
  "$(run lease heartbeat --run-dir "$HB_DIR")"

run lease acquire --run-dir "$HB_DIR" --run-id run-hb --plugin-data "$DATA" >/dev/null 2>&1
assert_eq "release prints the tombstone state" "released" "$(run lease release --run-dir "$HB_DIR")"
assert_eq "a released lease classifies released, not live" \
  "released" "$(run lease classify --run-dir "$HB_DIR")"
assert_contains "the tombstone is written into the lease, not by deleting it" \
  "$(cat "$HB_DIR/lease")" "state=released"

rc=0
run lease heartbeat --run-dir "$DATA/runs/demo/absent" >/dev/null 2>&1 || rc=$?
assert_exit "heartbeat on a directory that does not exist exits 2" 2 "$rc"

# --- Case 5b: acquire is where the write tree is pinned ---------------------
#
# acquire is the only command that CREATES a directory, so a wrong or invented
# --run-dir would otherwise get that directory created and a lease written into
# it. The skill keeps Bash specifically for state writes while promising a bare
# audit writes nothing into the target, so a run dir outside the plugin's own
# tree has to be refused rather than created.

OUTSIDE="$TEST_TMPDIR/target-repo/.claude"
rc=0
OUT=$(run lease acquire --run-dir "$OUTSIDE" --run-id run-x --plugin-data "$DATA" 2>&1) || rc=$?
assert_exit "a run dir outside <plugin-data>/runs/ is refused" 2 "$rc"
assert_contains "the refusal says it will not write outside the plugin tree" "$OUT" \
  "refusing to write outside"
if [[ -d "$OUTSIDE" ]]; then
  fail "the refused run dir must not be created" "$OUTSIDE exists"
else
  pass "the refused run dir was not created"
fi

rc=0
run lease acquire --run-dir "$DATA/runs/demo/../../escape" --run-id run-y --plugin-data "$DATA" >/dev/null 2>&1 || rc=$?
assert_exit "a run dir containing '..' is refused" 2 "$rc"

rc=0
OUT=$(env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" lease acquire --run-dir "$DATA/runs/demo/z" --run-id run-z 2>&1) || rc=$?
assert_exit "acquire without --plugin-data has nothing to check containment against, and refuses" 2 "$rc"

# --- Case 6: the append-only partial ----------------------------------------

P_DIR="$DATA/runs/demo/run-partial"
run lease acquire --run-dir "$P_DIR" --run-id run-partial --epoch 3 --plugin-data "$DATA" >/dev/null 2>&1
OUT=$(run partial append --run-dir "$P_DIR" --record '{"lane":"skills","attempt":1,"type":"start"}')
assert_eq "the partial is named for the epoch the lease holds" \
  "$P_DIR/findings.partial.3.jsonl" "$OUT"
assert_file "the partial exists after the first append" "$P_DIR/findings.partial.3.jsonl"
run partial append --run-dir "$P_DIR" \
  --record '{"lane":"skills","attempt":1,"type":"terminator","state":"open"}' >/dev/null
assert_eq "appends accumulate rather than rewriting the document" "2" \
  "$(wc -l <"$P_DIR/findings.partial.3.jsonl" | tr -d ' ')"
assert_contains "a lane terminator carrying open is readable from the artifact" \
  "$(cat "$P_DIR/findings.partial.3.jsonl")" '"state":"open"'

rc=0
OUT=$(run partial append --run-dir "$P_DIR" --record 'not json' 2>&1) || rc=$?
assert_exit "a record that is not a JSON object is refused" 2 "$rc"

rc=0
OUT=$(run partial append --run-dir "$P_DIR" --record '{"a":1}
{"b":2}' 2>&1) || rc=$?
assert_exit "a record spanning two lines is refused" 2 "$rc"
assert_contains "the refusal says why one line matters" "$OUT" "single line"

# A record that balances and ends in `}` but is not JSON must still be refused:
# a malformed row in an append-only artifact is permanent, and resume and
# assembly are its only readers.
rc=0
OUT=$(run partial append --run-dir "$P_DIR" --record '{bad json}' 2>&1) || rc=$?
assert_exit "a balanced-but-malformed record is refused, not appended" 2 "$rc"
rc=0
OUT=$(run partial append --run-dir "$P_DIR" --record '{"a":1' 2>&1) || rc=$?
assert_exit "a truncated record is refused" 2 "$rc"
rc=0
OUT=$(run partial append --run-dir "$P_DIR" --record '{"a":"}"}' 2>&1) || rc=$?
assert_exit "a brace inside a string does not fool the check" 0 "$rc"
assert_eq "and the malformed records left the artifact untouched" "3" \
  "$(wc -l <"$P_DIR/findings.partial.3.jsonl" | tr -d ' ')"

# The no-jq rung has to catch the same cases, since jq is optional here on
# purpose: failing the run's state-persistence path closed on a missing optional
# tool would cost the artifact the check exists to protect. Exercised by running
# with a PATH that has bash and nothing else, so the fallback is what answers.
REAL_BASH=$(command -v bash)
EMPTY_PATH="$TEST_TMPDIR/empty-path"
mkdir -p "$EMPTY_PATH"
nojq() { PATH="$EMPTY_PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$REAL_BASH" "$SCRIPT" "$@"; }
rc=0
nojq partial append --run-dir "$P_DIR" --record '{bad json}' >/dev/null 2>&1 || rc=$?
assert_exit "without jq, a balanced-but-malformed record is still refused" 2 "$rc"
rc=0
nojq partial append --run-dir "$P_DIR" --record '{"a":1' >/dev/null 2>&1 || rc=$?
assert_exit "without jq, a truncated record is still refused" 2 "$rc"
rc=0
nojq partial append --run-dir "$P_DIR" --record '{"a":"}"}' >/dev/null 2>&1 || rc=$?
assert_exit "without jq, a brace inside a string does not fool the fallback" 0 "$rc"
rc=0
nojq partial append --run-dir "$P_DIR" --record '{}' >/dev/null 2>&1 || rc=$?
assert_exit "without jq, an empty object is accepted" 0 "$rc"

# The epoch in the filename is the WRITER's, not whatever the lease now carries.
# A stale holder that wakes after an adopter incremented the epoch would
# otherwise read the adopter's value and append into the adopter's file — two
# writers interleaved under one attempt ordinal, the one failure the attempt
# machinery cannot absorb.
{
  printf 'run_id=run-partial\npid=1\nstate=active\nowner_epoch=9\n'
  printf 'started_at=x\nheartbeat_at=%s\nheartbeat_at_iso=x\n' "$(date -u +%s)"
  printf 'stale_after_s=1800\nskew_grace_s=60\n'
} >"$P_DIR/lease"
OUT=$(run partial append --run-dir "$P_DIR" --record '{"lane":"fenced"}' --epoch 3 2>/dev/null)
assert_eq "a fenced writer appends to its own epoch file, not the adopter's" \
  "$P_DIR/findings.partial.3.jsonl" "$OUT"
assert_contains "and the fence is reported rather than swallowed" \
  "$(run partial append --run-dir "$P_DIR" --record '{"lane":"fenced2"}' --epoch 3 2>&1 >/dev/null)" \
  "FENCED"
OUT=$(run partial append --run-dir "$P_DIR" --record '{"lane":"adopter"}' 2>/dev/null)
assert_eq "omitting --epoch still falls back to the lease's current epoch" \
  "$P_DIR/findings.partial.9.jsonl" "$OUT"

NO_LEASE="$DATA/runs/demo/run-noleash"
mkdir -p "$NO_LEASE"
rc=0
OUT=$(run partial append --run-dir "$NO_LEASE" --record '{"a":1}' 2>&1) || rc=$?
assert_exit "a partial is never written without a lease to classify it" 2 "$rc"
assert_contains "the refusal names the missing lease" "$OUT" "no lease at"

# --- Case 7: usage ----------------------------------------------------------

rc=0
run 2>/dev/null || rc=$?
assert_exit "no command exits 2" 2 "$rc"
rc=0
run nonsense 2>/dev/null || rc=$?
assert_exit "an unknown command exits 2" 2 "$rc"
rc=0
run lease nonsense --run-dir "$P_DIR" 2>/dev/null || rc=$?
assert_exit "an unknown lease action exits 2" 2 "$rc"
rc=0
run --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
