#!/usr/bin/env bash
# Regression tests for siblings-line.sh, black-box with a stubbed `gh` on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/siblings-line.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The merged pull request list comes from $TEST_TMPDIR/prs.json; a missing
# file fails the call.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
case "\$1 \$2" in
  "pr list") [[ -f "$TEST_TMPDIR/prs.json" ]] || exit 1; cat "$TEST_TMPDIR/prs.json" ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

# entry <number> <body> [closing-refs-json]
entry() {
  jq -n --argjson n "$1" --arg b "$2" --argjson c "${3:-[]}" \
    '{number: $n, body: $b, closingIssuesReferences: $c}'
}

prs() {
  jq -s . >"$TEST_TMPDIR/prs.json"
}

run() {
  : >"$TEST_TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

entry 12974 $'Refs: #12918\n\n## Why\n\nPart one.' | prs
out=$(run 12918)
assert_exit "a merged Refs: pull request exits 0" 0 "$?"
assert_eq "a merged Refs: pull request is named on a Siblings: line" "Siblings: #12974" "$out"
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "only merged pull requests are listed" "$calls" "--state merged"
assert_contains "the search names the Refs: line" "$calls" '"Refs: #12918" in:body'

printf '[]' >"$TEST_TMPDIR/prs.json"
out=$(run 12918)
assert_exit "no matching pull request exits 0" 0 "$?"
assert_silent "no matching pull request writes no Siblings: line" "$out"

{
  entry 30 $'Refs: #7\r\n'
  entry 20 $'## Why\n\nRefs: #7  \n'
} | prs
assert_eq "several siblings are listed oldest first" "Siblings: #20, #30" "$(run 7)"

{
  entry 21 "Closes #7" '[{"number":7}]'
  entry 22 $'Refs: #7\nCloses #8' '[{"number":8}]'
  entry 23 "Refs: #77"
  entry 24 "See Refs: #7 for context"
  entry 25 "Refs #7"
  entry 26 "Refs: #7, #8"
} | prs
out=$(run 7)
assert_silent "a closing, mid-line, other-issue or colon-less Refs is no sibling" "$out"

for n in $(seq 101 112); do entry "$n" "Refs: #7"; done | prs
assert_eq "at most 10 siblings are named, the newest" \
  "Siblings: #103, #104, #105, #106, #107, #108, #109, #110, #111, #112" "$(run 7)"

{
  entry 40 "Refs: #7"
  entry 41 "Refs: #8"
  entry 42 "Refs: #9"
} | prs
assert_eq "several closed issues share one Siblings: line" "Siblings: #40, #41" "$(run 7 8)"
assert_eq "one search runs per issue" "2" "$(grep -c 'pr list' "$TEST_TMPDIR/calls")"

rm -f "$TEST_TMPDIR/prs.json"
out=$(run 7 2>/dev/null)
assert_exit "a failed gh read exits 2" 2 "$?"
assert_silent "a failed gh read prints no line" "$out"

printf '[]' >"$TEST_TMPDIR/prs.json"
run 7 --repo acme/app >/dev/null
assert_contains "--repo reaches gh" "$(cat "$TEST_TMPDIR/calls")" "--repo acme/app"

run >/dev/null 2>&1
assert_exit "no issue number exits 1" 1 "$?"

run 'x7' >/dev/null 2>&1
assert_exit "a non-numeric issue exits 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
