#!/usr/bin/env bash
# Tests for the audit-suppressions entry point: scope (the change, --all,
# paths, scope.exclude), the correctness list from the team layer, the JSON
# document, the markdown report and the kept copy. Expected values are read
# off the fixture repository this file builds.
# test-scope: lib/suppression-scan.py plugins/code-metrics/scripts/dispatch.sh plugins/code-metrics/scripts/resolve-config.py
# shellcheck disable=SC2016 # `$(...)` and backticks here are fixture text, never expanded
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-suppressions.sh"
PY="${PYTHON:-python3}"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: [$3], actual: [$2]" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
export CODE_METRICS_HOME="$TMP/home"
export CODE_METRICS_REPORT_DIR="$TMP/reports"
mkdir -p "$REPO/docs/conventions" "$REPO/vendor" "$CODE_METRICS_HOME"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
printf '%s\n' 'a = 1  # noqa: E501' >"$REPO/old.py"
printf '%s\n' 'suppressions:' '  correctness_rules: [no-console]' >"$REPO/docs/conventions/code-metrics.yaml"
g add -A
g commit -q -m base
g switch -q -c topic
printf '%s\n' 'foo(); // eslint-disable-line no-console' >"$REPO/new.js"
printf '%s\n' 'x = 1  # noqa: E501 the URL is kept whole' >"$REPO/new.py"
printf '%s\n' '# shellcheck disable=SC2086' >"$REPO/\$(touch pwned).sh"
printf '%s\n' 'alert(1); // eslint-disable-line no-alert' >"$REPO/vendor/lib.js"
g add -A
g commit -q -m topic

doc_field() {
  "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print(eval(sys.argv[1], {"d": d}))
' "$1"
}

out="$(cd "$REPO" && BASH_COMPAT=51 bash "$SCRIPT" --json)"
assert_eq "the change run exits 0" 0 "$?"
assert_eq "the change reports only added lines, outside scope.exclude" \
  '$(touch pwned).sh:1 new.js:1 new.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"
assert_eq "the counts are one justified, two without a reason, one correctness rule" \
  '3 2 1' "$(printf '%s' "$out" | doc_field '"%d %d %d" % (d["counts"]["suppressions"], d["counts"]["unjustified"], d["counts"]["correctness"])')"
assert_eq "the correctness list and its layer come from the team file" \
  "['no-console'] team" "$(printf '%s' "$out" | doc_field '"%s %s" % (d["correctness_rules"]["rules"], d["correctness_rules"]["layer"])')"
assert_eq "the document names its skill and scope mode" \
  'audit-suppressions change' "$(printf '%s' "$out" | doc_field '"%s %s" % (d["skill"], d["scope"]["mode"])')"
if [[ -e "$REPO/pwned" ]]; then fail "a file name is never evaluated" "pwned exists"; else pass "a file name is never evaluated"; fi

out="$(cd "$REPO" && bash "$SCRIPT" --json --all)"
assert_eq "--all lists every suppression in the tree but the excluded one" \
  '$(touch pwned).sh:1 new.js:1 new.py:1 old.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"

out="$(cd "$REPO" && bash "$SCRIPT" --json old.py)"
assert_eq "an explicit path is scanned whole" 'old.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"

out="$(cd "$REPO" && bash "$SCRIPT")"
assert_eq "the markdown run exits 0" 0 "$?"
assert_contains "the markdown states the counts" "$out" "3 suppressions, 2 without a reason"
assert_contains "the markdown names the correctness rule" "$out" '`no-console`'
assert_contains "the markdown lists the unjustified line" "$out" "| new.js | 1 | eslint | no-console | no |"
kept=("$CODE_METRICS_REPORT_DIR"/audit-suppressions-*.json)
if [[ -f "${kept[0]}" ]]; then pass "the markdown run keeps the document"; else fail "the markdown run keeps the document" "none in $CODE_METRICS_REPORT_DIR"; fi
assert_contains "the markdown names the kept document" "$out" "${kept[0]}"

printf '%s\n' 'suppressions:' '  correctness_rules: no-console' >"$REPO/docs/conventions/code-metrics.yaml"
out="$(cd "$REPO" && bash "$SCRIPT" --json 2>"$TMP/err")"
assert_eq "an invalid correctness list never stops the run" 0 "$?"
assert_eq "an invalid team value falls back to the bundled empty list" '[] bundled default' \
  "$(printf '%s' "$out" | doc_field '"%s %s" % (d["correctness_rules"]["rules"], d["correctness_rules"]["layer"])')"
assert_contains "the warning names the key" "$(cat "$TMP/err")" "suppressions.correctness_rules"

(cd "$REPO" && bash "$SCRIPT" does-not-exist.py >/dev/null 2>&1)
assert_eq "a missing explicit path exits 2" 2 "$?"
(cd "$REPO" && bash "$SCRIPT" --bogus >/dev/null 2>&1)
assert_eq "an unknown flag exits 2" 2 "$?"
bash "$SCRIPT" --help 2>&1 | grep -q 'audit-suppressions.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
