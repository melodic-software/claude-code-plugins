#!/usr/bin/env bash
# Regression tests for detect-lanes.sh (self-contained, no external test lib).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/detect-lanes.sh"
# pathglob.py is the matcher behind --globs; naming it here keeps this suite
# in its affected-tests selection.
: "$SCRIPT_DIR/pathglob.py"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

out="$(bash "$SCRIPT" a/one.ts b/two.py c/three.sh d/four.go e/Five.cs f/notes.md g/six.MJS)"
assert_eq "extension map classifies every lane and skips markdown" \
  "$(printf 'typescript\ta/one.ts\npython\tb/two.py\nbash\tc/three.sh\ngo\td/four.go\ndotnet\te/Five.cs\ntypescript\tg/six.MJS')" "$out"

out="$(bash "$SCRIPT" --disable python a/one.ts b/two.py)"
assert_eq "--disable drops the lane" "$(printf 'typescript\ta/one.ts')" "$out"

out="$(bash "$SCRIPT" --globs 'bash=scripts/**/*.bats,*.zsh' scripts/x/y.bats top.zsh other.sh)"
assert_eq "--globs replaces the extension map for that lane" \
  "$(printf 'bash\tscripts/x/y.bats\nbash\ttop.zsh')" "$out"

out="$(bash "$SCRIPT" $'dir\x5cwin.py')"
assert_eq "backslashes are normalized to forward slashes" "$(printf 'python\tdir/win.py')" "$out"

out="$(bash "$SCRIPT")"
rc=$?
assert_eq "no files is an empty result with exit 0" "0:" "$rc:$out"

bash "$SCRIPT" --globs nonsense a.py >/dev/null 2>&1
assert_eq "malformed --globs is a usage error" "2" "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
