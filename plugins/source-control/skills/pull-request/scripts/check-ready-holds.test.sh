#!/usr/bin/env bash
# Regression tests for check-ready-holds.sh, black-box with a stubbed `gh` on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-ready-holds.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The pull request's facts come from $TEST_TMPDIR/pr.json; an issue's state
# from $TEST_TMPDIR/issue-<n>, and a missing file fails the lookup.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
case "\$1 \$2" in
  "pr view") [[ -f "$TEST_TMPDIR/pr.json" ]] || exit 1; cat "$TEST_TMPDIR/pr.json" ;;
  "api "*)
    for a in "\$@"; do [[ "\$a" == repos/* ]] && n="\${a##*/}"; done
    [[ -f "$TEST_TMPDIR/issue-\$n" ]] || exit 1
    cat "$TEST_TMPDIR/issue-\$n"
    ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

# pr <title> <body> [labels-json] [closing-refs-json]
pr() {
  jq -n --arg t "$1" --arg b "$2" --argjson l "${3:-[]}" --argjson c "${4:-[]}" \
    '{title: $t, body: $b, labels: $l, closingIssuesReferences: $c}' >"$TEST_TMPDIR/pr.json"
}

ref() {
  printf '{"number":%s,"url":"https://github.com/acme/app/issues/%s","repository":{"name":"app","owner":{"login":"acme"}}}' "$1" "$1"
}

run() {
  : >"$TEST_TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

pr "feat(x): add a thing" "Closes #10" "[]" "[$(ref 10)]"
echo open >"$TEST_TMPDIR/issue-10"
out=$(run 7)
assert_exit "an unheld pull request with an open linked issue exits 0" 0 "$?"
assert_silent "an unheld pull request prints nothing" "$out"
assert_contains "the issue state is read over REST" "$(cat "$TEST_TMPDIR/calls")" "repos/acme/app/issues/10 --jq .state"

pr "feat(x): add a thing" "" '[{"name":"do-not-merge"}]'
out=$(run 7)
assert_exit "the do-not-merge label holds the flip" 3 "$?"
assert_contains "the label hold names the label" "$out" "do-not-merge"

pr "feat(x): add a thing" "" '[{"name":"Do-Not-Merge"}]'
run 7 >/dev/null
assert_exit "the label matches whatever its case" 3 "$?"

pr "feat(x): add a thing" "Please do not merge until the release."
out=$(run 7)
assert_exit "a 'do not merge' body holds the flip" 3 "$?"
assert_contains "the body hold says so" "$out" "body"

pr "feat(x): add a thing" "Please don't merge until the migration lands."
run 7 >/dev/null
assert_exit "a \"don't merge\" body holds the flip" 3 "$?"

pr "feat(x): add a thing" $'Please don’t merge yet.'
run 7 >/dev/null
assert_exit "a typographic apostrophe in don't still holds the flip" 3 "$?"

pr "feat(x): add a thing" $'## Summary\n\nHold: a human merges this\n'
out=$(run 7)
assert_exit "a body line starting Hold: holds the merge only, not the flip" 0 "$?"
assert_silent "a Hold: line reports nothing" "$out"

pr "feat(x): add a thing" "Adds the do-not-merge label check to the merge lane."
run 7 >/dev/null
assert_exit "a body that only names the label is not a hold" 0 "$?"

pr "test(harness-config): WIP: pin permission suites" ""
out=$(run 7)
assert_exit "a WIP marker after the type prefix holds the flip" 3 "$?"
assert_contains "the WIP hold names the title" "$out" "WIP"

pr $'WIP: thing \e[2Jnow' ""
assert_eq "control bytes are stripped from the quoted title" 'title: a WIP marker in "WIP: thing [2Jnow"' "$(run 7)"

pr "wip(guardrails): wrapper-argv resolver" ""
run 7 >/dev/null
assert_exit "a wip type holds the flip" 3 "$?"

pr "fix(cache): wipe stale entries" ""
run 7 >/dev/null
assert_exit "a title word that only starts with wip is not a hold" 0 "$?"

pr "feat(x): add a thing" "Closes #10, closes #11" "[]" "[$(ref 10),$(ref 11)]"
echo open >"$TEST_TMPDIR/issue-10"
echo closed >"$TEST_TMPDIR/issue-11"
out=$(run 7)
assert_exit "a closed linked issue refuses the flip" 3 "$?"
assert_contains "the refusal names the closed issue" "$out" "acme/app#11"
assert_not_contains "an open linked issue is not reported" "$out" "acme/app#10"

pr "test(x): WIP: thing" "do not merge" '[{"name":"do-not-merge"}]' "[$(ref 11)]"
echo closed >"$TEST_TMPDIR/issue-11"
out=$(run 7)
assert_eq "every hold is reported, one per line" "4" "$(grep -c . <<<"$out")"

assert_contains "a github.com issue names its host" "$(cat "$TEST_TMPDIR/calls")" "--hostname github.com"

pr "feat(x): add a thing" "" "[]" "[$(ref 10),{\"number\":13,\"url\":null,\"repository\":{\"name\":\"app\",\"owner\":{\"login\":\"acme\"}}}]"
run 7 >/dev/null 2>&1
assert_exit "a malformed closing reference fails closed" 2 "$?"

rm -f "$TEST_TMPDIR/issue-12"
pr "feat(x): add a thing" "Closes #12" "[]" "[$(ref 12)]"
run 7 >/dev/null 2>&1
assert_exit "an unreadable linked issue fails closed" 2 "$?"

rm -f "$TEST_TMPDIR/pr.json"
run 7 >/dev/null 2>&1
assert_exit "an unreadable pull request fails closed" 2 "$?"

run >/dev/null 2>&1
assert_exit "no pull request number exits 1" 1 "$?"

pr "feat(x): add a thing" ""
run 7 --repo acme/app >/dev/null
assert_contains "--repo reaches gh" "$(cat "$TEST_TMPDIR/calls")" "--repo acme/app"

pr "feat(x): add a thing" $'## Related\n\nDraft: multi-session container\n'
out=$(run 7 --unattended)
assert_exit "an unattended run refuses a draft a person asked for" 3 "$?"
assert_contains "the refusal names the Draft: line" "$out" "Draft: multi-session container"

pr "feat(x): add a thing" $'## Related\n\nDraft: requested early look\n'
run 7 --unattended >/dev/null
assert_exit "an unattended run refuses a requested early-look draft" 3 "$?"

out=$(run 7)
assert_exit "a person running ready may flip a requested draft" 0 "$?"
assert_silent "an attended run reports no hold for a Draft: line" "$out"

pr "feat(x): add a thing" $'## Summary\n\nThe draft: still rough.\n'
out=$(run 7 --unattended)
assert_exit "an unattended run without a Draft: line passes" 0 "$?"
assert_silent "an unattended run without a Draft: line prints nothing" "$out"

[[ $FAILED -eq 0 ]] || exit 1
