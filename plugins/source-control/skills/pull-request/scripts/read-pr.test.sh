#!/usr/bin/env bash
# Regression tests for read-pr.sh, black-box with a stubbed `gh` on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-pr.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The stub logs each call's arguments, so a case can check what reached gh.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
case "\$1 \$2" in
  "pr view")
    [[ "\$3" == 404 ]] && { echo "no pull requests found" >&2; exit 1; }
    case " \$* " in *" --repo acme/ghe-app "*) url=https://ghe.example/acme/ghe-app/pull/7 ;; *) url=https://github.com/acme/app/pull/7 ;; esac
    printf '{"number":7,"url":"%s","state":"OPEN","isDraft":true,"title":"t","baseRefName":"main","headRefName":"feat/7-x","files":[{"path":"a.md"}]}' "\$url"
    ;;
  "pr diff") printf 'diff --git a/a.md b/a.md\n' ;;
  "pr list")
    [[ "\${GH_STUB_LIST_FAIL:-}" == 1 ]] && exit 1
    printf '[{"number":1,"headRefName":"fix/improve-a"},{"number":2,"headRefName":"feat/other"},{"number":3,"headRefName":"docs/improve-b"}]'
    ;;
  "api repos/acme/app") [[ "\${GH_STUB_API_FAIL:-}" == 1 ]] && exit 1; echo public ;;
  "api --hostname") echo private ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

run() {
  : >"$TEST_TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

out=$(run view 7)
assert_eq "view merges the repository visibility into the facts" "PUBLIC" "$(jq -r .visibility <<<"$out")"
assert_eq "view keeps the pull request's own fields" "main" "$(jq -r .baseRefName <<<"$out")"
assert_contains "view asks gh for the head and base oids" "$(cat "$TEST_TMPDIR/calls")" "headRefOid"
assert_contains "view asks gh for the merge commit" "$(cat "$TEST_TMPDIR/calls")" "mergeCommit"

out=$(GH_STUB_API_FAIL=1 run view 7)
assert_eq "a failed visibility lookup reads UNKNOWN, never a guess" "UNKNOWN" "$(jq -r .visibility <<<"$out")"

out=$(run view 7 --repo acme/ghe-app)
assert_eq "visibility on another host asks that host" "PRIVATE" "$(jq -r .visibility <<<"$out")"
assert_contains "the host comes from the pull request URL" "$(cat "$TEST_TMPDIR/calls")" "api --hostname ghe.example repos/acme/ghe-app"

run view 404 >/dev/null 2>&1
assert_exit "no pull request exits 2" 2 "$?"

out=$(run view 7 --diff)
assert_contains "view --diff prints the diff" "$out" "diff --git a/a.md b/a.md"

out=$(run view 7 --diff --out "$TEST_TMPDIR/pr.diff")
assert_silent "--out leaves stdout empty" "$out"
assert_eq "--out writes the diff to the file" "diff --git a/a.md b/a.md" "$(cat "$TEST_TMPDIR/pr.diff")"
run view 7 --out "$TEST_TMPDIR/facts.json" >/dev/null
assert_eq "--out writes the facts to the file" "PUBLIC" "$(jq -r .visibility "$TEST_TMPDIR/facts.json")"

out=$(run view)
assert_eq "view with no number reads the current branch's pull request" "pr view --json" "$(head -1 "$TEST_TMPDIR/calls" | cut -d' ' -f1-3)"

out=$(run list --head-match '^[a-z]+/improve-')
assert_eq "list --head-match keeps only matching head branches" "1,3" "$(jq -r 'map(.number) | join(",")' <<<"$out")"
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list lifts gh's 30-row default" "$calls" "--limit 1000"
assert_contains "list defaults to open pull requests" "$calls" "--state open"

run list --head feat/x --state all >/dev/null
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list passes --head through" "$calls" "--head feat/x"
assert_contains "list passes --state through" "$calls" "--state all"

run list --head feat/x --search '#42' >/dev/null
calls=$(cat "$TEST_TMPDIR/calls")
assert_contains "list passes --search through as one argument" "$calls" "--head feat/x --search #42"
run list --search '#42' >/dev/null
assert_contains "list --search works without --head" "$(cat "$TEST_TMPDIR/calls")" "--search #42"
run view 7 --search x >/dev/null 2>&1
assert_exit "--search on view exits 1" 1 "$?"

GH_STUB_LIST_FAIL=1 run list >/dev/null 2>&1
assert_exit "a failed list exits 2, never an empty array" 2 "$?"
run list --head-match '(' >/dev/null 2>&1
assert_exit "an invalid --head-match exits 1" 1 "$?"
run >/dev/null 2>&1
assert_exit "no action exits 1" 1 "$?"
assert_contains "list asks for the merge commit" "$calls" "mergeCommit"

run list --state draft >/dev/null 2>&1
assert_exit "an unknown --state exits 1" 1 "$?"
run view 7 --head x >/dev/null 2>&1
assert_exit "a list flag on view exits 1" 1 "$?"
run list --diff >/dev/null 2>&1
assert_exit "--diff on list exits 1" 1 "$?"
run frobnicate >/dev/null 2>&1
assert_exit "an unknown action exits 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
