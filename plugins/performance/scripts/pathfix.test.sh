#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
PATHFIX="$SCRIPT_DIR/pathfix.py"
readonly PATHFIX

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

run_pathfix() { capture "$HARNESS_PYTHON" "$PATHFIX" "$1"; }

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT
printf 'content\n' >"$WORK/real-file.txt"

run_pathfix "$WORK/real-file.txt"
assert_eq "an existing file resolves" "0" "$RUN_RC"
assert_contains "the resolution is reported" "resolved=" "$RUN_OUT"

# discriminating-skip-required: silent rewriting of a working path is the
# failure mode this whole file has to avoid, and this is the case that proves
# it does not happen.
run_pathfix "$WORK/real-file.txt"
if [[ "$RUN_OUT" == *"note=None"* ]]; then
  pass "a working spelling is left alone, with no conversion note"
else
  fail "a working spelling is left alone" "note=None" "$RUN_OUT"
fi

run_pathfix "/d/definitely/not/here/at/all.txt"
assert_eq "a nonexistent path fails" "1" "$RUN_RC"
assert_contains "the failure lists the spellings tried" "tried=" "$RUN_OUT"
assert_contains "the failure explains the two-spelling hazard" "two spellings" "$RUN_OUT"

conversions="$(
  cd "$SCRIPT_DIR" && "$HARNESS_PYTHON" - 2>&1 <<'PY'
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
