#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SELF_DIR/check-cant-fail-scan.sh"
SCAN="$SELF_DIR/../plugins/testing/skills/audit/scripts/cant-fail-scan.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

CLEAN_TEST='import unittest


class T(unittest.TestCase):
    def test_sum(self):
        self.assertEqual(sum([1, 2]), 3)
'
HOLLOW_TEST='import unittest


class T(unittest.TestCase):
    def test_x(self):
        pass
'

n=0
new_repo() {
  n=$((n + 1))
  r="$TMP_ROOT/r$n"
  if ! { mkdir -p "$r/pkg/tests" &&
    git_init_test_repo "$r" >/dev/null &&
    printf 'base\n' >"$r/README.md" &&
    printf '%s' "$CLEAN_TEST" >"$r/pkg/tests/test_base.py" &&
    git_test_config "$r" add -A &&
    git_test_config "$r" commit -qm base &&
    git_test_config "$r" tag base; }; then
    printf 'cannot build fixture %s\n' "$r" >&2
    exit 2
  fi
}

put() {
  if ! { mkdir -p "$1/$(dirname "$2")" &&
    printf '%s' "$3" >"$1/$2" &&
    git_test_config "$1" add -- "$2" &&
    git_test_config "$1" commit -qm "$2" >/dev/null; }; then
    printf 'cannot commit %s in %s\n' "$2" "$1" >&2
    exit 2
  fi
}

gate() {
  local want="$1" name="$2" repo="$3" rc
  shift 3
  [[ -n "$repo" && -d "$repo/.git" ]] || {
    printf 'not a fixture repository: %s\n' "$repo" >&2
    exit 2
  }
  (cd "$repo" && bash "$GATE" "$@") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"
  rc=$?
  OUT="$(cat "$TMP_ROOT/out")"
  ERR="$(cat "$TMP_ROOT/err")"
  if [[ $rc -eq $want ]]; then pass "$name"; else bad "$name" "exit $rc, want $want; out: $OUT; err: $ERR"; fi
}

has() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else bad "$1" "missing '$3' in: $2"; fi
}

new_repo
put "$r" README.md 'changed
'
gate 0 "a diff with no test file passes" "$r" base
has "it reports the gate not applicable, counting the files it looked at" "$OUT" \
  "Not applicable: 1 file(s) changed since base, none a test file the scan covers"

new_repo
gate 0 "HEAD at the base passes" "$r" base
has "it says HEAD is the base" "$OUT" "Not applicable: HEAD is base"

new_repo
put "$r" README.md 'changed
'
put "$r" README.md 'base
'
gate 2 "an empty diff with commits on top is an environment error, not a pass" "$r" base
has "it says nothing changed" "$ERR" "no file changed since base, yet HEAD is not base"
if [[ -z "$OUT" ]]; then pass "an empty diff prints no clean statement"; else bad "an empty diff prints no clean statement" "$OUT"; fi

new_repo
put "$r" pkg/tests/test_new.py "$CLEAN_TEST"
gate 0 "a clean changed test file passes" "$r" base
has "it names the scanned file" "$OUT" "clean: pkg/tests/test_new.py"

new_repo
put "$r" pkg/tests/test_hollow.py "$HOLLOW_TEST"
gate 1 "a changed test with no assertion fails" "$r" base
has "the finding is on stderr" "$ERR" "rule-zero-assertion"
if [[ "$OUT" != *rule-zero-assertion* ]]; then pass "the finding is not on stdout"; else bad "the finding is not on stdout" "$OUT"; fi

new_repo
git_test_config "$r" rm -q pkg/tests/test_base.py && git_test_config "$r" commit -qm rm >/dev/null
gate 0 "a deleted test file is not scanned" "$r" base
has "a deletion alone is not applicable" "$OUT" "Not applicable"

new_repo
put "$r" build/tests/test_hollow.py "$HOLLOW_TEST"
put "$r" plugins/p/evals/fixtures/test_hollow.py "$HOLLOW_TEST"
gate 0 "hollow tests under pruned directories are skipped" "$r" base
has "pruned files leave the diff not applicable" "$OUT" "Not applicable"
gate 0 "the whole-tree scan of the same tree passes too" "$r"

new_repo
put "$r" pkg/tests/test_locked.py "$CLEAN_TEST"
chmod 000 "$r/pkg/tests/test_locked.py"
if [[ -r "$r/pkg/tests/test_locked.py" ]]; then
  pass "skipped: this user can read a mode-000 file"
else
  gate 2 "an unreadable changed test file fails closed" "$r" base
fi
chmod 644 "$r/pkg/tests/test_locked.py"

new_repo
gate 0 "the whole-tree scan of a clean tree passes" "$r"
put "$r" pkg/tests/test_hollow.py "$HOLLOW_TEST"
gate 1 "the whole-tree scan finds a hollow test" "$r"

gate 2 "an unknown base is an environment error" "$r" no-such-ref

WORKFLOW="$SELF_DIR/../.github/workflows/pr-require-checks.yml"
awk '/^      - name: Check every test for tests that cannot fail$/ { on = 1; next }
  on && /^        run: \|$/ { body = 1; next }
  on && body && /^          / { print substr($0, 11); next }
  on && body { exit }' "$WORKFLOW" >"$TMP_ROOT/check-tests.sh"
new_repo
put "$r" pkg/tests/test_hollow.py "$HOLLOW_TEST"
mkdir -p "$r/scripts"
cp "$GATE" "$r/scripts/"
ln -s "$(cd "$SELF_DIR/../plugins" && pwd)" "$r/plugins"
step() {
  local rc
  (cd "$r" && bash -e "$TMP_ROOT/check-tests.sh") >"$TMP_ROOT/out" 2>&1
  rc=$?
  OUT="$(cat "$TMP_ROOT/out")"
  if [[ $rc -eq $1 ]]; then pass "$2"; else bad "$2" "exit $rc, want $1: $OUT"; fi
}
if [[ -s "$TMP_ROOT/check-tests.sh" ]]; then
  step 1 "check-tests scans the whole tree and finds a hollow test"
  rm "$r/pkg/tests/test_hollow.py"
  step 0 "check-tests passes a clean whole tree"
else
  bad "check-tests has a run: | body" "none found in $WORKFLOW"
fi

want="$(sed -n '/^collect_files() {/,/^}/p' "$SCAN" | grep -oE -- "-name [^ )]+" | awk '$2 != "fixtures" {print $2}' | sort)"
got="$(sed -n "s/^PRUNED='(^|\/)(\(.*\))\/|.*/\1/p" "$GATE" | tr '|' '\n' | sed 's/\\//g' | sort)"
if [[ -n "$want" && "$want" == "$got" ]] && grep -q "\-path '\*/evals/fixtures'" "$SCAN" && grep -qF '|(^|/)evals/fixtures/' "$GATE"; then
  pass "PRUNED names the scanner's pruned directories"
else
  bad "PRUNED names the scanner's pruned directories" "scanner: ${want//$'\n'/ } gate: ${got//$'\n'/ }"
fi

test_harness::report
