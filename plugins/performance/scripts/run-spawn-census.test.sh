#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
DRIVER="$SCRIPT_DIR/run-spawn-census.sh"
readonly DRIVER

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

run_driver() { capture bash "$DRIVER" "$@"; }

WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/run-spawn-census.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
export PERF_HARNESS_LEDGER_DIR="$WORK/ledger"
SHIM="$WORK/shim"

cat >"$WORK/stable.sh" <<'STABLE'
#!/usr/bin/env bash
for ((i = 0; i < $1; i++)); do
  printf 'x\n' | sed 's/x/y/' >/dev/null
done
STABLE

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

run_driver --shim-dir "$SHIM" --tool sed \
  --before-label stable-before --after-label stable-after \
  --before "bash '$WORK/stable.sh' 3" --after "bash '$WORK/stable.sh' 1"
assert_eq "a stable before/after pair exits 0" "0" "$RUN_RC"
assert_contains "the counter delta is reported" "delta=-2" "$RUN_OUT"
assert_contains "the cold run is labeled separately" "cold  spawns=" "$RUN_OUT"
assert_contains "stability is stated, not assumed" "both arms agreed" "$RUN_OUT"

# discriminating-skip-required: this case is the only proof that the rule 1
# agreement gate fires at all.
run_driver --shim-dir "$SHIM" --tool sed \
  --before-label climbing --after-label unused \
  --before "bash '$WORK/climbing.sh' '$WORK/counter'" --after "bash '$WORK/stable.sh' 1"
assert_eq "an arm whose warm runs disagree is refused" "2" "$RUN_RC"
assert_contains "the refusal cites rule 1" "rule 1" "$RUN_OUT"
assert_contains "the refusal rules out a cold-cache artifact" "discarded as cold" "$RUN_OUT"
assert_contains "the refusal forbids reporting a delta" "Do not report a before/after delta" "$RUN_OUT"

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
