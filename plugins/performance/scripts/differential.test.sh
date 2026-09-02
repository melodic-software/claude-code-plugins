#!/usr/bin/env bash
# Tests for differential.py, the pre-change versus post-change behavior proof.
#
# Two cases carry the weight, and neither is about detecting a real difference:
#
#   * NEVER EXERCISED. Two arms that both produced nothing and both failed the
#     same way are not "parity", they are a harness that never ran the subject.
#     Reported as parity, that is a confident wrong verdict about behavior.
#   * SELF-DISCLOSURE. Byte-identical stdout is only a valid bar when the arms
#     cannot differ merely by living at different paths, so an arm that prints
#     its own location invalidates the comparison rather than failing it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
DIFFERENTIAL="$SCRIPT_DIR/differential.py"
readonly DIFFERENTIAL

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
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no *$2*" "$3"; fi
}

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/base" "$WORK/cand"

RUN_OUT=""
RUN_RC=0
run_differential() {
  RUN_OUT="$("$HARNESS_PYTHON" "$DIFFERENTIAL" "$@" 2>&1)"
  RUN_RC=$?
}

# A subject whose verdict depends on the mode it was given and the command it
# was handed on stdin. The optional-group form in the config is what lets the
# matrix cover "no --mode at all", the shape a caller gets by default.
cat >"$WORK/base/subject.py" <<'SUBJECT'
import json
import sys

mode = sys.argv[2] if len(sys.argv) > 2 else "none"
command = json.load(sys.stdin)["tool_input"]["command"]
verdict = "DENY" if "rm -rf" in command else "ALLOW"
print(f"{mode}:{verdict}")
sys.exit(2 if verdict == "DENY" else 0)
SUBJECT
cp "$WORK/base/subject.py" "$WORK/cand/subject.py"

cat >"$WORK/config.json" <<'CONFIG'
{
  "argv": ["{{python}}", "{{subject}}", ["--mode", "{{mode}}"]],
  "matrix": {"mode": [null, "belt"]},
  "corpus": ["git status --porcelain", "rm -rf /"],
  "stdin_json": {"tool_input": {"command": "{{corpus}}"}}
}
CONFIG

# --- 1. identical arms report parity, and the matrix really ran ---
run_differential --baseline "$WORK/base/subject.py" --candidate "$WORK/cand/subject.py" \
  --config "$WORK/config.json"
assert_eq "identical arms exit 0" "0" "$RUN_RC"
assert_contains "parity is stated in full" "PARITY: byte-identical stdout and exit code" "$RUN_OUT"
assert_contains "both matrix combinations ran" "matrix combinations  : 2" "$RUN_OUT"
assert_contains "all four invocations were compared" "invocations compared : 4" "$RUN_OUT"
# Four distinct results prove the null-mode optional group and the corpus both
# discriminate; one distinct result would mean the matrix changed nothing.
assert_contains "the corpus and matrix produced distinct results" "baseline=4 candidate=4" "$RUN_OUT"

# --- 1b. a stderr-only difference is DISCLOSED, not silently outside the bar ---
# stderr is deliberately not part of the parity bar, because diagnostics carry
# timings and paths two copies legitimately differ on. What must not happen is
# the gap being invisible: "byte-identical stdout and exit code" is a narrower
# claim than "behavior did not change", and a reader cannot tell them apart
# unless the difference is stated.
# discriminating-skip-required: this case is the only thing standing between a
# narrow verdict and a reader who believes it was a broad one.
mkdir -p "$WORK/noisy"
cat >"$WORK/base/noisy.py" <<'QUIET'
import sys

print("same stdout")
QUIET
cat >"$WORK/cand/noisy.py" <<'NOISY'
import sys

print("same stdout")
print("a warning only the candidate emits", file=sys.stderr)
NOISY
cat >"$WORK/noisy-config.json" <<'NOISYCONFIG'
{
  "argv": ["{{python}}", "{{subject}}"],
  "corpus": ["only-one"]
}
NOISYCONFIG
run_differential --baseline "$WORK/base/noisy.py" --candidate "$WORK/cand/noisy.py" \
  --config "$WORK/noisy-config.json"
assert_eq "a stderr-only difference still reports parity" "0" "$RUN_RC"
assert_contains "the parity verdict is still stated" "PARITY:" "$RUN_OUT"
assert_contains "the stderr gap is disclosed with a count" \
  "stderr differed on 1 of 1 invocations" "$RUN_OUT"
assert_contains "the disclosure names what is unverified" "it is UNVERIFIED here" "$RUN_OUT"

# --- 2. a real behavior change is reported as a mismatch, not smoothed over ---
cat >"$WORK/cand/subject.py" <<'CHANGED'
import json
import sys

mode = sys.argv[2] if len(sys.argv) > 2 else "none"
command = json.load(sys.stdin)["tool_input"]["command"]
verdict = "ASK" if "rm -rf" in command else "ALLOW"
print(f"{mode}:{verdict}")
sys.exit(1 if verdict == "ASK" else 0)
CHANGED
run_differential --baseline "$WORK/base/subject.py" --candidate "$WORK/cand/subject.py" \
  --config "$WORK/config.json"
assert_eq "a changed arm exits 1" "1" "$RUN_RC"
assert_contains "the mismatch count is reported" "MISMATCHES: 2" "$RUN_OUT"
assert_contains "the mismatch shows both verdicts" "DENY" "$RUN_OUT"
assert_not_contains "a mismatching run never claims parity" "PARITY:" "$RUN_OUT"

# --- 3. two arms that never ran are refused, NOT reported as parity ---
# discriminating-skip-required: this case is the only proof that a symmetric
# failure of both arms is distinguished from genuine parity.
cat >"$WORK/base/dead.py" <<'DEAD'
import sys

sys.exit(3)
DEAD
cp "$WORK/base/dead.py" "$WORK/cand/dead.py"
run_differential --baseline "$WORK/base/dead.py" --candidate "$WORK/cand/dead.py" \
  --config "$WORK/config.json"
assert_eq "two identically-failing silent arms are refused" "2" "$RUN_RC"
assert_contains "the refusal denies it is parity" "That is not parity" "$RUN_OUT"
assert_contains "the refusal names the confident-wrong-verdict shape" "confident, wrong verdict" "$RUN_OUT"
assert_not_contains "a never-exercised run never claims parity" "PARITY:" "$RUN_OUT"

# --- 4. an arm that discloses its own path invalidates byte-exactness ---
cat >"$WORK/base/leaky.py" <<'LEAKY'
import sys

print(__file__)
LEAKY
cp "$WORK/base/leaky.py" "$WORK/cand/leaky.py"
cat >"$WORK/leaky-config.json" <<'LEAKYCONFIG'
{
  "argv": ["{{python}}", "{{subject}}"],
  "corpus": ["only-one"]
}
LEAKYCONFIG
run_differential --baseline "$WORK/base/leaky.py" --candidate "$WORK/cand/leaky.py" \
  --config "$WORK/leaky-config.json"
assert_eq "an arm disclosing its own path is refused" "2" "$RUN_RC"
assert_contains "the disclosure is reported" "SELF-DISCLOSURE:" "$RUN_OUT"
assert_contains "the refusal explains why byte-exactness is invalid here" \
  "differ purely by living at different paths" "$RUN_OUT"

# --- 5. preconditions ---
run_differential --baseline "$WORK/base/subject.py" --candidate "$WORK/base/subject.py" \
  --config "$WORK/config.json"
assert_eq "comparing a file with itself is refused" "2" "$RUN_RC"
assert_contains "the refusal names the empty comparison" "compare a file with itself" "$RUN_OUT"

cat >"$WORK/empty-config.json" <<'EMPTY'
{"argv": ["{{python}}", "{{subject}}"], "corpus": []}
EMPTY
run_differential --baseline "$WORK/base/subject.py" --candidate "$WORK/cand/subject.py" \
  --config "$WORK/empty-config.json"
assert_eq "an empty corpus is refused" "2" "$RUN_RC"

run_differential --baseline "$WORK/base/does-not-exist.py" --candidate "$WORK/cand/subject.py" \
  --config "$WORK/config.json"
assert_eq "a missing baseline is refused" "2" "$RUN_RC"
assert_contains "the refusal lists the spellings tried" "any spelling this harness tried" "$RUN_OUT"

# --- 6. a harvest that finds nothing is refused, never silently empty ---
cat >"$WORK/suite.py" <<'SUITE'
def test_nothing():
    assert True
SUITE
cat >"$WORK/harvest-config.json" <<'HARVEST'
{
  "argv": ["{{python}}", "{{subject}}"],
  "corpus": ["fallback"],
  "harvest": {"helpers": ["run_guard"], "arg_index": 0}
}
HARVEST
run_differential --baseline "$WORK/base/subject.py" --candidate "$WORK/cand/subject.py" \
  --config "$WORK/harvest-config.json" --harvest-from "$WORK/suite.py"
assert_eq "an empty harvest is refused" "2" "$RUN_RC"
assert_contains "the refusal names the false coverage claim" "claim coverage" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: differential parity and refusals"
exit 0
