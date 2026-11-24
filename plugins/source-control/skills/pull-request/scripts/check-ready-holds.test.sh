#!/usr/bin/env bash
# Regression tests for check-ready-holds.sh, black-box with a stubbed `gh` on PATH.
# test-scope: plugins/source-control/.claude-plugin/plugin.json

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
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
filter=""
prev=""
for a in "\$@"; do
  [[ "\$prev" == --jq ]] && filter="\$a"
  [[ "\$a" == repos/* ]] && endpoint="\$a"
  prev="\$a"
done
serve() {
  [[ -f "$TEST_TMPDIR/\$1" ]] || exit 1
  if [[ -n "\$filter" ]]; then jq -rc "\$filter" "$TEST_TMPDIR/\$1"; else cat "$TEST_TMPDIR/\$1"; fi
}
case "\$1 \$2" in
  "pr view") [[ -f "$TEST_TMPDIR/pr.json" ]] || exit 1; cat "$TEST_TMPDIR/pr.json" ;;
  "api "*)
    case "\$endpoint" in
      */events\?*) serve events.json ;;
      */comments\?*) serve comments.json ;;
      repos/example-org/standards/git/ref/heads/main) serve standards-head.json ;;
      repos/example-org/standards/commits/main) serve standards-tag.json ;;
      repos/example-org/standards/contents/*) serve standards-trusted.json ;;
      */contents/docs/conventions/source-control.yaml)
        [[ -f "$TEST_TMPDIR/team.yaml" ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        cat "$TEST_TMPDIR/team.yaml"
        ;;
      */contents/*) serve trusted.json ;;
      *)
        n="\${endpoint##*/}"
        [[ -f "$TEST_TMPDIR/issue-\$n" ]] || exit 1
        cat "$TEST_TMPDIR/issue-\$n"
        ;;
    esac
    ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

pr() {
  jq -n --arg t "$1" --arg b "$2" --argjson l "${3:-[]}" --argjson c "${4:-[]}" \
    '{title: $t, body: $b, labels: $l, closingIssuesReferences: $c, url: "https://github.com/acme/app/pull/7"}' >"$TEST_TMPDIR/pr.json"
}

comment() {
  jq -cn --arg t "$1" --arg ty "$2" --argjson id "$3" --arg l "$4" --arg b "$5" \
    '{created_at: $t, body: $b, user: {type: $ty, id: $id, login: $l}, performed_via_github_app: null}'
}

comments() {
  local IFS=,
  printf '[%s]\n' "$*" >"$TEST_TMPDIR/comments.json"
}

EVAL_LINE='<!-- pr-hold reason=eval -->'
LANES_APP='lanes-app[bot]'
DNM='[{"name":"do-not-merge"}]'

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

REAL_JQ=$(command -v jq)
CRLF_DIR="$TEST_TMPDIR/crlf"
mkdir -p "$CRLF_DIR"
printf '#!/usr/bin/env bash
"%s" "$@" | sed "s/$/\r/"
' "$REAL_JQ" >"$CRLF_DIR/jq"
chmod +x "$CRLF_DIR/jq"
pr "feat(x): add a thing" "Closes #10, closes #11" "[]" "[$(ref 10),$(ref 11)]"
echo open >"$TEST_TMPDIR/issue-11"
: >"$TEST_TMPDIR/calls"
out=$(PATH="$CRLF_DIR:$STUB_DIR:$PATH" bash "$SCRIPT" 7)
assert_exit "two closing issues read through CRLF jq output exit 0" 0 "$?"
assert_contains "the first issue is read without a stray carriage return" "$(cat "$TEST_TMPDIR/calls")" "repos/acme/app/issues/10 --jq .state"

pr "feat(x): add a thing" "" '[{"name":"do-not-merge"}]'
out=$(run 7)
assert_exit "the do-not-merge label holds the flip" 3 "$?"
assert_contains "the label hold names the label" "$out" "do-not-merge"

pr "feat(x): add a thing" "" '[{"name":"Do-Not-Merge"}]'
run 7 >/dev/null
assert_exit "the label matches whatever its case" 3 "$?"

printf '{"version":1,"actors":[{"id":101,"login":"owner","kind":"human"},{"id":202,"login":"%s","kind":"bot"}]}\n' "$LANES_APP" >"$TEST_TMPDIR/trusted.json"
printf '%s\n' '[{"event":"labeled","created_at":"2026-11-21T06:00:00Z","label":{"name":"do-not-merge"}},{"event":"labeled","created_at":"2026-11-21T07:00:00Z","label":{"name":"do-not-merge"}},{"event":"unlabeled","created_at":"2026-11-21T08:00:00Z","label":{"name":"do-not-merge"}}]' >"$TEST_TMPDIR/events.json"
pr "feat(x): add a thing" "" "$DNM"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner $'Held for the eval.\n\n'"$EVAL_LINE")"
out=$(run 7 2>/dev/null)
assert_exit "an eval-only do-not-merge from a listed human lets the flip go on" 0 "$?"
assert_silent "an eval-only do-not-merge reports no hold" "$out"
assert_not_contains "the check leaves the label on" "$(cat "$TEST_TMPDIR/calls")" "labels/"
run 7 --unattended >/dev/null 2>&1
assert_exit "an unattended run flips an eval-only do-not-merge too" 0 "$?"
PATH="$CRLF_DIR:$STUB_DIR:$PATH" bash "$SCRIPT" 7 >/dev/null 2>&1
assert_exit "an eval-only do-not-merge read through CRLF jq output lets the flip go on" 0 "$?"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner '<!-- pr-hold reason=release -->')"
out=$(run 7 2>/dev/null)
assert_exit "a do-not-merge with another hold reason holds the flip" 3 "$?"
assert_contains "the refusal names the other reason" "$out" "reason=release"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner "$EVAL_LINE")" "$(comment 2026-11-21T07:10:00Z User 101 owner '<!-- pr-hold reason=release -->')"
run 7 >/dev/null 2>&1
assert_exit "an eval line beside another reason since the label holds the flip" 3 "$?"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner 'Holding this one.')"
out=$(run 7 2>/dev/null)
assert_exit "a do-not-merge with no hold reason line holds the flip" 3 "$?"
assert_contains "the refusal says no reason line was found" "$out" "no pr-hold reason line"

comments "$(comment 2026-11-21T06:30:00Z User 101 owner "$EVAL_LINE")"
run 7 >/dev/null 2>&1
assert_exit "an eval line posted before the newest label event holds the flip" 3 "$?"

comments "$(comment 2026-11-21T07:00:05Z User 303 stranger "$EVAL_LINE")"
run 7 >/dev/null 2>&1
assert_exit "an eval line from an unlisted account holds the flip" 3 "$?"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner $'```\n'"$EVAL_LINE"$'\n```')"
run 7 >/dev/null 2>&1
assert_exit "an eval line inside a fenced block is not a reason line" 3 "$?"

comments "$(comment 2026-11-21T07:00:05Z Bot 202 "$LANES_APP" "$EVAL_LINE")"
run 7 >/dev/null 2>&1
assert_exit "an eval line from a bot with no lanes App setting holds the flip" 3 "$?"

APP_PLUGIN="$TEST_TMPDIR/app-plugin"
mkdir -p "$APP_PLUGIN/skills/pull-request/scripts" "$APP_PLUGIN/skills/babysit-prs/scripts"
cp "$SCRIPT" "$APP_PLUGIN/skills/pull-request/scripts/"
printf 'babysit_python() { printf %q; }\n' "{\"issue_status_app_login\":\"$LANES_APP\"}" >"$APP_PLUGIN/skills/babysit-prs/scripts/babysit-python.sh"
PATH="$STUB_DIR:$PATH" bash "$APP_PLUGIN/skills/pull-request/scripts/check-ready-holds.sh" 7 >/dev/null 2>&1
assert_exit "an eval line from the lanes App the settings name lets the flip go on" 0 "$?"

comments "$(comment 2026-11-21T07:00:05Z User 101 owner "$EVAL_LINE")"
mv "$TEST_TMPDIR/trusted.json" "$TEST_TMPDIR/standards-trusted.json"
printf '{"ref":"refs/heads/main","object":{"sha":"%s"}}\n' "$(printf '5%.0s' {1..40})" >"$TEST_TMPDIR/standards-head.json"
printf '{"sha":"%s"}\n' "$(printf '6%.0s' {1..40})" >"$TEST_TMPDIR/standards-tag.json"
printf 'trusted_actors_source: standards\nstandards_repository: example-org/standards\n' >"$TEST_TMPDIR/team.yaml"
run 7 >/dev/null 2>&1
assert_exit "an opted-in repository reads the standards list" 0 "$?"
assert_contains "the standards list is read at main's commit" "$(cat "$TEST_TMPDIR/calls")" "repos/example-org/standards/contents/components/trusted-actors/trusted-actors.json?ref=5555555555555555555555555555555555555555"
assert_not_contains "the repository copy is not read" "$(cat "$TEST_TMPDIR/calls")" ".github/standards/trusted-actors"
assert_not_contains "main is read by its full ref, never a same-named tag" "$(cat "$TEST_TMPDIR/calls")" "standards/commits/main"
rm -f "$TEST_TMPDIR/standards-head.json"
run 7 >/dev/null 2>&1
assert_exit "an unresolved standards branch leaves the label holding, a tag named main notwithstanding" 3 "$?"
rm -f "$TEST_TMPDIR/standards-tag.json"
for team in 'trusted_actors_source: elsewhere' 'trusted_actors_source: [standards]' \
  'trusted_actors_source: standards' $'trusted_actors_source: standards\nstandards_repository: not-a-pair' \
  $'trusted_actors_source: standards\nstandards_repository: [example-org/standards]'; do
  printf '%s\n' "$team" >"$TEST_TMPDIR/team.yaml"
  run 7 >/dev/null 2>&1
  assert_exit "an unreadable source ($team) leaves the label holding" 3 "$?"
done
printf 'trusted_actors_source: repository\n' >"$TEST_TMPDIR/team.yaml"
run 7 >/dev/null 2>&1
assert_exit "a repository source with no copy leaves the label holding" 3 "$?"
mv "$TEST_TMPDIR/standards-trusted.json" "$TEST_TMPDIR/trusted.json"
run 7 >/dev/null 2>&1
assert_exit "a repository source reads its own copy" 0 "$?"
rm -f "$TEST_TMPDIR/team.yaml" "$TEST_TMPDIR/trusted.json"
run 7 >/dev/null 2>&1
assert_exit "an unreadable trusted-actors list leaves the label holding" 3 "$?"
rm -f "$TEST_TMPDIR/events.json" "$TEST_TMPDIR/comments.json"

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

pr "feat(x): add a thing" $'## Summary\n\nHold: do not merge until X lands.\n'
run 7 >/dev/null
assert_exit "a Hold: line saying do not merge holds the merge only, not the flip" 0 "$?"

pr "feat(x): add a thing" $'## Summary\n\n  > hold: don\'t merge yet\n'
run 7 >/dev/null
assert_exit "a quoted lower-case hold: line saying don't merge does not hold the flip" 0 "$?"

pr "feat(x): add a thing" $'Hold: a human merges this\n\nPlease do not merge until the release.\n'
run 7 >/dev/null
assert_exit "do not merge outside a Hold: line still holds the flip" 3 "$?"

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

pr "feat(pr-pipeline): derive the issue-lane WIP cap from the merge rate" ""
out=$(run 7)
assert_exit "a WIP mid-title is not a hold" 0 "$?"
assert_silent "a WIP mid-title reports nothing" "$out"

pr "docs: explain wip limits (WIP cap)" ""
run 7 >/dev/null
assert_exit "WIP inside parentheses with other words is not a hold" 0 "$?"

for title in "WIP thing" "wip: thing" "[WIP] thing" "(WIP) thing" "feat: WIP thing" "feat(x)!: wip: thing" "feat(x): [wip] thing" "feat(x): thing (WIP)"; do
  pr "$title" ""
  run 7 >/dev/null
  assert_exit "the WIP marker in '$title' holds the flip" 3 "$?"
done

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

for line in 'draft: multi-session container' 'Draft:  multi-session container' 'Draft: please hold until the demo' '> Draft: requested early look' $'Draft: multi-session container\r'; do
  pr "feat(x): add a thing" $'## Related\n\n'"$line"$'\n'
  run 7 --unattended >/dev/null
  rc=$?
  assert_exit "an unattended run holds the Draft: variant $(printf '%q' "$line")" 3 "$rc"
done

pr "feat(x): add a thing" $'## Related\r\n\r\nDraft: multi-session container\r\n'
out=$(run 7 --unattended)
assert_exit "an unattended run holds a Draft: line in a CRLF body" 3 "$?"
assert_not_contains "the reason carries no carriage return" "$out" $'\r'

pr "feat(x): add a thing" $'## Related\n\nDraft: requested early look \e[2J\a\n'
out=$(run 7 --unattended)
assert_exit "a Draft: line with control bytes still holds" 3 "$?"
assert_not_contains "control bytes are stripped from the reason" "$out" $'\e'

pr "feat(x): add a thing" $'## Related\n\nDraft:\n'
run 7 --unattended >/dev/null
assert_exit "an unattended run holds a bare Draft: line" 3 "$?"

pr "feat(x): add a thing" $'## Related\n\nRedraft: the summary after review\n'
out=$(run 7 --unattended)
assert_exit "a Redraft: line is not a hold line" 0 "$?"
assert_silent "a Redraft: line prints nothing" "$out"

pr "feat(x): add a thing" $'## Summary\n\nSee Draft: requested early look\n'
out=$(run 7 --unattended)
assert_exit "a mid-line Draft: is not a hold line" 0 "$?"
assert_silent "a mid-line Draft: prints nothing" "$out"

pr "feat(x): add a thing" $'## Related\n\nDraft: multi-session container\n'

out=$(run 7)
assert_exit "a person running ready may flip a requested draft" 0 "$?"
assert_silent "an attended run reports no hold for a Draft: line" "$out"

pr "feat(x): add a thing" $'## Summary\n\nThe draft: still rough.\n'
out=$(run 7 --unattended)
assert_exit "an unattended run without a Draft: line passes" 0 "$?"
assert_silent "an unattended run without a Draft: line prints nothing" "$out"

[[ $FAILED -eq 0 ]] || exit 1
