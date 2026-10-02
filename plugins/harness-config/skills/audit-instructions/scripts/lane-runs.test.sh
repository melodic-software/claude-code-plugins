#!/usr/bin/env bash
# Regression tests for lane-runs.sh (assertions from test-helpers.sh beside this
# file; both ship with the plugin). The lease cases drive audit-pass's real
# run-state.sh, since attach reuses it rather than reimplementing the lease.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LR="$SCRIPT_DIR/lane-runs.sh"
RUN_STATE="$SCRIPT_DIR/../../audit-pass/scripts/run-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# write_bytes <path> <count> <line-width>: <count> bytes of text in lines of
# <line-width> characters (newline included), so bytes-per-line is controlled.
write_bytes() {
  mkdir -p "$(dirname "$1")"
  awk -v n="$2" -v w="$3" 'BEGIN {
    line = ""; for (i = 1; i < w; i++) line = line "x"
    out = 0
    while (out + w <= n) { print line; out += w }
    rest = n - out; if (rest > 0) { s = ""; for (i = 0; i < rest; i++) s = s "y"; printf "%s", s }
  }' >"$1"
}

F="$TEST_TMPDIR/tree"
write_bytes "$F/alpha/one.md" 1500 50
write_bytes "$F/beta/one.md" 1000 50
write_bytes "$F/beta/two.md" 1000 50
write_bytes "$F/gamma/big.md" 3000 50
write_bytes "$F/gamma/small.md" 1500 50
write_bytes "$F/gamma/tiny.md" 500 50

INPUT="alpha	one	$F/alpha/one.md
beta	one	$F/beta/one.md
beta	two	$F/beta/two.md
gamma	big	$F/gamma/big.md
gamma	small	$F/gamma/small.md
gamma	tiny	$F/gamma/tiny.md"

partition() { # partition <input> -> stdout; budget 4000 bytes
  printf '%s\n' "$1" | bash "$LR" partition --window-tokens 1000 --fraction 1 --bytes-per-token 4
}
field() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1 == k {print substr($0, length(k) + 2)}'; }

# --- Case 1: --help ------------------------------------------------------------
rc=0
OUT=$(bash "$LR" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help names the partition command" "$OUT" "lane-runs.sh partition"

# --- Case 2: plugin-atomic packing and split-by-skill -----------------------------
P=$(partition "$INPUT")
assert_eq "budget bytes is window x fraction x bytes-per-token" "4000" "$(field "$P" budget_bytes)"
assert_contains "alpha and beta pack whole into one lane" "$P" "	alpha,beta"
assert_contains "gamma exceeds the budget and is split" "$P" "split=gamma:2"
assert_contains "gamma's split lanes are keyed by skill" "$P" "	gamma/big"
assert_contains "the split packs small and tiny together" "$P" "	gamma/small,gamma/tiny"
assert_not_contains "no unit is over budget here" "$P" "over_budget="
assert_eq "three lanes" "3" "$(field "$P" lanes)"
LANE_FILES=$(printf '%s\n' "$P" | awk -F'\t' '$1 == "file"' | wc -l | tr -d ' ')
assert_eq "every input file is assigned to a lane" "6" "$LANE_FILES"

# --- Case 3: a single unit over the budget still gets a lane and is named -------
write_bytes "$F/delta/huge.md" 6000 50
P2=$(partition "delta	huge	$F/delta/huge.md")
assert_contains "an oversized unit is named on an over_budget line" "$P2" "over_budget=delta/huge"
assert_eq "an oversized unit still gets one lane" "1" "$(field "$P2" lanes)"

# --- Case 4: the partition is a function of the input set, not its order --------
REVERSED=$(printf '%s\n' "$INPUT" | tac 2>/dev/null || printf '%s\n' "$INPUT" | tail -r)
P3=$(partition "$REVERSED")
assert_eq "reordered input yields the same partition digest" \
  "$(field "$P" partition_digest)" "$(field "$P3" partition_digest)"

# --- Case 5: the line budget is derived from measured bytes per line -------------
write_bytes "$F/wide/one.md" 2000 100
PW=$(partition "wide	one	$F/wide/one.md")
assert_eq "50-byte lines measure 50.0 bytes per line" "50.0" "$(field "$P" bytes_per_line)"
assert_eq "50-byte lines give an 80-line budget" "80" "$(field "$P" budget_lines)"
assert_eq "100-byte lines give a 40-line budget from the same byte budget" "40" "$(field "$PW" budget_lines)"

# --- Case 6: partition usage errors ------------------------------------------------
rc=0
printf '%s\n' "$INPUT" | bash "$LR" partition --window-tokens 1000 --fraction 1 >/dev/null 2>&1 || rc=$?
assert_exit "partition without --bytes-per-token is a usage error" 2 "$rc"
rc=0
printf '%s\n' "$INPUT" | bash "$LR" partition --window-tokens 1000 --fraction 1.5 --bytes-per-token 4 >/dev/null 2>&1 || rc=$?
assert_exit "a fraction above 1 is refused" 2 "$rc"
rc=0
printf 'x\ty\t%s/nope.md\n' "$F" | bash "$LR" partition --window-tokens 1000 --fraction 1 --bytes-per-token 4 >/dev/null 2>&1 || rc=$?
assert_exit "a missing input file is refused" 2 "$rc"

# --- Case 7: the lane digest covers every input ------------------------------------
BASE_PARAMS=(--param catalog_version=1.22.0 --param conflict_criteria_version=1.5.0
  --param prompt_digest=sha256:aa --param harness_version=2.1.300 --param target_model=opus-5
  --param scope=all --param opinion=false --param no_stopping_condition=false)
digest() { bash "$LR" digest "$@"; }
D1=$(digest --partition-digest sha256:p1 "${BASE_PARAMS[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
D1b=$(digest --partition-digest sha256:p1 "${BASE_PARAMS[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
assert_eq "an unchanged input set yields the same digest" "$D1" "$D1b"
assert_contains "the digest is sha256-prefixed" "$D1" "sha256:"

REORDERED_PARAMS=(--param target_model=opus-5 --param scope=all --param opinion=false
  --param no_stopping_condition=false --param catalog_version=1.22.0
  --param conflict_criteria_version=1.5.0 --param prompt_digest=sha256:aa --param harness_version=2.1.300)
D1c=$(digest --partition-digest sha256:p1 "${REORDERED_PARAMS[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
assert_eq "param order does not change the digest" "$D1" "$D1c"

for change in catalog_version=1.23.0 conflict_criteria_version=1.6.0 prompt_digest=sha256:bb \
  harness_version=2.1.301 target_model=sonnet-5 scope=skills opinion=true no_stopping_condition=true; do
  key="${change%%=*}"
  CHANGED=()
  for ((i = 0; i < ${#BASE_PARAMS[@]}; i += 2)); do
    if [[ "${BASE_PARAMS[i + 1]%%=*}" == "$key" ]]; then
      CHANGED+=(--param "$change")
    else
      CHANGED+=("${BASE_PARAMS[i]}" "${BASE_PARAMS[i + 1]}")
    fi
  done
  D2=$(digest --partition-digest sha256:p1 "${CHANGED[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
  if [[ "$D2" != "$D1" ]]; then pass "changing $key changes the digest"; else fail "changing $key changes the digest" "digest unchanged"; fi
done

D3=$(digest --partition-digest sha256:p2 "${BASE_PARAMS[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
if [[ "$D3" != "$D1" ]]; then pass "changing the partition changes the digest"; else fail "changing the partition changes the digest" "unchanged"; fi
D4=$(digest --partition-digest sha256:p1 "${BASE_PARAMS[@]}" -- "$F/beta/one.md" "$F/alpha/one.md")
if [[ "$D4" != "$D1" ]]; then pass "the file order is part of the digest"; else fail "the file order is part of the digest" "unchanged"; fi
cp "$F/alpha/one.md" "$TEST_TMPDIR/alpha.bak"
printf 'edit\n' >>"$F/alpha/one.md"
D5=$(digest --partition-digest sha256:p1 "${BASE_PARAMS[@]}" -- "$F/alpha/one.md" "$F/beta/one.md")
cp "$TEST_TMPDIR/alpha.bak" "$F/alpha/one.md"
if [[ "$D5" != "$D1" ]]; then pass "editing a file changes the digest"; else fail "editing a file changes the digest" "unchanged"; fi

rc=0
ERR=$(digest --partition-digest sha256:p1 --param catalog_version=1 -- "$F/alpha/one.md" 2>&1 >/dev/null) || rc=$?
assert_exit "a digest missing required params is refused" 2 "$rc"
assert_contains "the refusal names a missing key" "$ERR" "harness_version"

# --- Case 8: resume plan against per-lane run files ----------------------------------
RUN="$TEST_TMPDIR/data/audit-instructions/runs/key/20260928T010000Z"
mkdir -p "$RUN/lanes"
MARK_A=$(bash "$LR" marker --lane lane-a --digest sha256:da)
printf '# lane a\nfinding\n%s\n\n' "$MARK_A" >"$RUN/lanes/lane-a.md"
printf '# lane b\nhalf a report\n' >"$RUN/lanes/lane-b.md"
printf '# lane c\n%s\n' "$(bash "$LR" marker --lane lane-c --digest sha256:old)" >"$RUN/lanes/lane-c.md"
printf '# lane e\n%s\ntrailing text after the marker\n' "$(bash "$LR" marker --lane lane-e --digest sha256:de)" >"$RUN/lanes/lane-e.md"
PLAN=$(printf 'lane-a\tsha256:da\nlane-b\tsha256:db\nlane-c\tsha256:new\nlane-d\tsha256:dd\nlane-e\tsha256:de\n' |
  bash "$LR" plan --run-dir "$RUN")
assert_contains "a lane ending in its matching marker is reused" "$PLAN" "lane-a	reuse	complete"
assert_contains "a lane without a marker is rerun as incomplete" "$PLAN" "lane-b	rerun	incomplete"
assert_contains "a lane whose digest changed is rerun" "$PLAN" "lane-c	rerun	digest-changed"
assert_contains "a lane with no report is rerun as missing" "$PLAN" "lane-d	rerun	missing"
assert_contains "a marker that is not the last line does not count" "$PLAN" "lane-e	rerun	incomplete"

# --- Case 9: end to end, an interrupted run resumes only its unfinished lane ---------
PROJ=$(partition "$INPUT")
PD=$(field "$PROJ" partition_digest)
LANES=$(printf '%s\n' "$PROJ" | awk -F'\t' '$1 == "lane" {print $2}')
lane_digest() { # lane_digest <lane-id> [extra digest args]
  local id="$1"
  shift
  local files
  mapfile -t files < <(printf '%s\n' "$PROJ" | awk -F'\t' -v id="$id" '$1 == "file" && $2 == id {print $3}')
  digest --partition-digest "$PD" "$@" -- "${files[@]}"
}
RUN2="$TEST_TMPDIR/data/audit-instructions/runs/key/20260928T020000Z"
mkdir -p "$RUN2/lanes"
i=0
PLAN_IN=""
for id in $LANES; do
  d=$(lane_digest "$id" "${BASE_PARAMS[@]}")
  PLAN_IN+="$id"$'\t'"$d"$'\n'
  i=$((i + 1))
  if [[ "$i" -lt 3 ]]; then
    printf 'report\n%s\n' "$(bash "$LR" marker --lane "$id" --digest "$d")" >"$RUN2/lanes/$id.md"
  else
    printf 'report cut off by the usage limit\n' >"$RUN2/lanes/$id.md"
  fi
done
RESUME=$(printf '%s' "$PLAN_IN" | bash "$LR" plan --run-dir "$RUN2")
assert_eq "after an interruption only the unfinished lane reruns" "1" \
  "$(printf '%s\n' "$RESUME" | awk -F'\t' '$2 == "rerun"' | wc -l | tr -d ' ')"
PLAN_IN2=""
for id in $LANES; do
  CHANGED=("${BASE_PARAMS[@]}")
  CHANGED[1]=catalog_version=1.23.0
  PLAN_IN2+="$id"$'\t'"$(lane_digest "$id" "${CHANGED[@]}")"$'\n'
done
RESUME2=$(printf '%s' "$PLAN_IN2" | bash "$LR" plan --run-dir "$RUN2")
assert_eq "a catalog version change reruns every lane" "3" \
  "$(printf '%s\n' "$RESUME2" | awk -F'\t' '$2 == "rerun"' | wc -l | tr -d ' ')"

# --- Case 10: latest run id under the state key ----------------------------------------
RUNS="$TEST_TMPDIR/data/audit-instructions/runs/key"
mkdir -p "$RUNS/not-a-run" "$RUNS/20260101T000000Z"
assert_eq "latest picks the newest run id" "20260928T020000Z" "$(bash "$LR" latest --runs-dir "$RUNS")"
rc=0
bash "$LR" latest --runs-dir "$TEST_TMPDIR/none" >/dev/null 2>&1 || rc=$?
assert_exit "latest with no run exits 1" 1 "$rc"

# --- Case 11: attach refuses a live lease and names its window ---------------------------
PD_ROOT="$TEST_TMPDIR/data/audit-instructions"
LIVE="$PD_ROOT/runs/key/20260928T030000Z"
bash "$RUN_STATE" lease acquire --run-dir "$LIVE" --run-id 20260928T030000Z --plugin-data "$PD_ROOT" >/dev/null
rc=0
ERR=$(bash "$LR" attach --run-dir "$LIVE" 2>&1 >/dev/null) || rc=$?
assert_exit "attach refuses a live lease with exit 4" 4 "$rc"
assert_contains "the refusal names heartbeat_at" "$ERR" "heartbeat_at=20"
assert_contains "the refusal names stale_after_s" "$ERR" "stale_after_s=1800"

bash "$RUN_STATE" lease release --run-dir "$LIVE" >/dev/null
OUT=$(bash "$LR" attach --run-dir "$LIVE")
assert_contains "a released lease attaches" "$OUT" "verdict=released"
assert_contains "adoption takes the next epoch" "$OUT" "next_epoch=2"

STALE="$PD_ROOT/runs/key/20260928T040000Z"
bash "$RUN_STATE" lease acquire --run-dir "$STALE" --run-id 20260928T040000Z --plugin-data "$PD_ROOT" --stale-after 1 >/dev/null
awk 'index($0, "heartbeat_at=") == 1 {print "heartbeat_at=1"; next} {print}' "$STALE/lease" >"$STALE/lease.new" && mv "$STALE/lease.new" "$STALE/lease"
OUT=$(bash "$LR" attach --run-dir "$STALE")
assert_contains "a stale lease attaches" "$OUT" "verdict=stale"

OUT=$(bash "$LR" attach --run-dir "$RUN2")
assert_contains "a run with no lease attaches as missing" "$OUT" "verdict=missing"
assert_contains "a leaseless run adopts at epoch 1" "$OUT" "next_epoch=1"

# --- Summary ------------------------------------------------------------------------------
printf '\n'
if [[ "$FAILED" -gt 0 ]]; then
  printf '%d of %d checks FAILED.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'All %d checks passed.\n' "$CASE_NUM"
