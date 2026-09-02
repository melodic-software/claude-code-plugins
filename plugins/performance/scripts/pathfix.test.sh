#!/usr/bin/env bash
# Tests for pathfix.py, the MSYS-versus-native path spelling resolver.
#
# The case that carries the weight is a REAL file addressed by the MSYS spelling
# on a host whose Python is a native Windows build. That combination is the
# mirror of harness-integrity.md rule 6, it is the default on the host this
# plugin was built from, and without it the Python harnesses report a phantom
# missing file for a file that plainly exists.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
PATHFIX="$SCRIPT_DIR/pathfix.py"
readonly PATHFIX

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
run_pathfix() {
  RUN_OUT="$("$HARNESS_PYTHON" "$PATHFIX" "$1" 2>&1)"
  RUN_RC=$?
}

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT
printf 'content\n' >"$WORK/real-file.txt"

# --- 1. a real file addressed in this shell's own spelling always resolves ---
# $WORK is the MSYS spelling under Git Bash and an ordinary POSIX path
# elsewhere, so this case is meaningful on both.
run_pathfix "$WORK/real-file.txt"
assert_eq "an existing file resolves" "0" "$RUN_RC"
assert_contains "the resolution is reported" "resolved=" "$RUN_OUT"

# --- 2. a path that resolves for the interpreter is NEVER rewritten ---
# discriminating-skip-required: silent rewriting of a working path is the
# failure mode this whole file has to avoid, and this is the case that proves
# it does not happen.
run_pathfix "$WORK/real-file.txt"
if [[ "$RUN_OUT" == *"note=None"* ]]; then
  pass "a working spelling is left alone, with no conversion note"
else
  fail "a working spelling is left alone" "note=None" "$RUN_OUT"
fi

# --- 3. a nonexistent path fails and names every spelling it tried ---
run_pathfix "/d/definitely/not/here/at/all.txt"
assert_eq "a nonexistent path fails" "1" "$RUN_RC"
assert_contains "the failure lists the spellings tried" "tried=" "$RUN_OUT"
assert_contains "the failure explains the two-spelling hazard" "two spellings" "$RUN_OUT"

# --- 4. the conversion itself is correct in both directions ---
conversions="$(cd "$SCRIPT_DIR" && "$HARNESS_PYTHON" - 2>&1 <<'PY'
import pathfix

# portability-ok: Python string data inside a heredoc, not a shell regex; the
# backslashes are the native path spelling under test.
print(pathfix.native_to_msys("D:\\worktrees\\repo"))
print(pathfix.msys_to_native("/d/worktrees/repo").replace("\\", "/"))
PY
)"
assert_contains "a native path folds to the MSYS spelling" "/d/worktrees/repo" "$conversions"
assert_contains "an MSYS path folds to the native spelling" "D:/worktrees/repo" "$conversions"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: pathfix spelling resolution"
exit 0
