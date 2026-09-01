#!/usr/bin/env bash
# Tests for run-spawn-census.sh, the before/after driver.
#
# The case that matters most is the UNSTABLE one: a driver that reports a
# before/after delta from a harness whose own repeated runs disagree is
# reporting its own variance as the change. harness-integrity.md rule 1 makes
# that a hard failure, and this suite proves the failure actually fires.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
DRIVER="$SCRIPT_DIR/run-spawn-census.sh"
readonly DRIVER

# Inline test helpers: self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s - expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "*$2*" "$3"; fi
}

RUN_OUT=""
RUN_RC=0
run_driver() {
  RUN_OUT="$(bash "$DRIVER" "$@" 2>&1)"
  RUN_RC=$?
}

# Not under the system temporary root: the shim directory rejection would
# otherwise make every case unrunnable.
WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/run-spawn-census.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
export PERF_HARNESS_LEDGER_DIR="$WORK/ledger"
SHIM="$WORK/shim"

# A stable subject: exactly $1 sed spawns, every run.
cat >"$WORK/stable.sh" <<'STABLE'
#!/usr/bin/env bash
for ((i = 0; i < $1; i++)); do
  printf 'x\n' | sed 's/x/y/' >/dev/null
done
STABLE

# A subject whose spawn count CLIMBS on every run. Only builtins touch the
# counter (read and printf), so the drift shows up purely as sed spawns.
cat >"$WORK/climbing.sh" <<'CLIMBING'
#!/usr/bin/env bash
n=0
if [[ -f "$1" ]]; then read -r n <"$1"; fi
n=$((n + 1))
printf '%s\n' "$n" >"$1"
for ((i = 0; i < n; i++)); do
  printf 'x\n' | sed 's/x/y/' >/dev/null
done
CLIMBING

# --- 1. a stable pair reports a delta and says the arms agreed ---
run_driver --shim-dir "$SHIM" --tool sed \
  --before-label stable-before --after-label stable-after \
  --before "bash '$WORK/stable.sh' 3" --after "bash '$WORK/stable.sh' 1"
assert_eq "a stable before/after pair exits 0" "0" "$RUN_RC"
assert_contains "the counter delta is reported" "delta=-2" "$RUN_OUT"
assert_contains "the cold run is labelled separately" "cold  spawns=" "$RUN_OUT"
assert_contains "stability is stated, not assumed" "both arms agreed" "$RUN_OUT"

# --- 2. a subject whose WARM runs disagree is a hard failure ---
# Run 1 is discarded as cold, so this cannot be a cold-cache artifact: the
# climbing subject counts 2 then 3 on the two warm runs.
# discriminating-skip-required: this case is the only proof that the rule 1
# agreement gate fires at all.
run_driver --shim-dir "$SHIM" --tool sed \
  --before-label climbing --after-label unused \
  --before "bash '$WORK/climbing.sh' '$WORK/counter'" --after "bash '$WORK/stable.sh' 1"
assert_eq "an arm whose warm runs disagree is refused" "2" "$RUN_RC"
assert_contains "the refusal cites rule 1" "rule 1" "$RUN_OUT"
assert_contains "the refusal rules out a cold-cache artifact" "discarded as cold" "$RUN_OUT"
assert_contains "the refusal forbids reporting a delta" "Do not report a before/after delta" "$RUN_OUT"

# --- 3. preconditions ---
run_driver --shim-dir "$SHIM" --after "bash -c 'printf ok'"
assert_eq "a missing --before is refused" "2" "$RUN_RC"

run_driver --shim-dir "$SHIM" --warm 1 --before "bash -c 'printf ok'" --after "bash -c 'printf ok'"
assert_eq "--warm 1 is refused" "2" "$RUN_RC"
assert_contains "the refusal explains why one run agrees with nothing" "agree with nothing" "$RUN_OUT"

run_driver --shim-dir "$SHIM" --before "bash D:/repo/hook.sh" --after "bash -c 'printf ok'"
assert_eq "a drive-letter path inside an arm command is refused" "2" "$RUN_RC"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: run-spawn-census"
exit 0
