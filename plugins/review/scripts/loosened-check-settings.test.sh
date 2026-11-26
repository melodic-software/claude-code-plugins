#!/usr/bin/env bash
# test-scope: plugins/review/schemas/review.schema.json plugins/review/skills/setup/scripts/setup-apply.mjs plugins/review/lib/setup-apply.mjs plugins/review/lib/yaml-subset.mjs
# test-scope: plugins/review/.claude-plugin/plugin.json plugins/review/lib/parse-concern-value.sh plugins/review/lib/resolve-convention-home.sh plugins/review/lib/yaml-subset.awk
# test-scope: plugins/review/scripts/fixtures/standards-ref-heads-main.json plugins/review/scripts/fixtures/standards-trusted-actors.json
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/loosened-check-settings.mjs"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: node is not on PATH\n' >&2
  exit 0
fi

g() { git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "${@:2}"; }
line_of() { printf '%s\n' "$1" | grep "^$2: " | head -1; }

new_repo() {
  local r="$TEST_TMPDIR/$1"
  mkdir -p "$r/docs/conventions"
  g "$r" init -q
  printf '%s' "$2" >"$r/docs/conventions/review.yaml"
  g "$r" add docs/conventions/review.yaml
  g "$r" commit -q -m base
  g "$r" update-ref refs/remotes/origin/main HEAD
  g "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  printf '%s' "$r"
}

R1="$(new_repo c1 $'loosened_check_verdict: fail\nloosened_check_patterns:\n  - "ci/checks/**"\n  - "text:continue-on-error"\n')"
printf 'loosened_check_verdict: note\nloosened_check_patterns:\n  - "text:continue-on-error"\n' >"$R1/docs/conventions/review.yaml"
g "$R1" commit -q -a -m head
out="$(node "$RESOLVE" --root "$R1" --ref origin/main 2>&1)"
assert_eq "case 1: the resolver exits 0" "0" "$?"
assert_contains "case 1: the head's note does not relax the default-branch fail" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: fail"
assert_contains "case 1: the pattern the head dropped is still resolved" \
  "$(line_of "$out" loosened_check_patterns)" '"ci/checks/**"'
assert_contains "case 1: the pattern both copies hold is resolved" \
  "$(line_of "$out" loosened_check_patterns)" '"text:continue-on-error"'

out="$(node "$RESOLVE" --root "$R1" --ref origin/main --verdict-option note)"
assert_contains "case 2: a user note under a repository fail resolves fail" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: fail"
R2="$(new_repo c2 $'loosened_check_verdict: note\n')"
out="$(node "$RESOLVE" --root "$R2" --ref origin/main --verdict-option fail)"
assert_contains "case 2: a user fail over a repository note resolves fail" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: fail (userConfig)"
out="$(node "$RESOLVE" --root "$R2" --ref origin/main)"
assert_contains "case 2: a repository note with no user option resolves note" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: note"
# shellcheck disable=SC2016 # the literal, unexpanded placeholder is the input under test
out="$(node "$RESOLVE" --root "$R2" --ref origin/main --verdict-option '${user_config.loosened_check_verdict}')"
assert_contains "case 2: an unrendered placeholder is unset" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: note"

printf '%s' '["test/**", "ci/checks/**"]' >"$TEST_TMPDIR/patterns-c3"
out="$(node "$RESOLVE" --root "$R1" --ref origin/main --patterns-file "$TEST_TMPDIR/patterns-c3")"
assert_eq "case 3: user and repository patterns are unioned, each once" \
  'loosened_check_patterns: ["test/**","ci/checks/**","text:continue-on-error"] (userConfig, docs/conventions/review.yaml)' \
  "$(line_of "$out" loosened_check_patterns)"

R4="$(new_repo c4 $'fanout_diversity: lens\n')"
out="$(node "$RESOLVE" --root "$R4" --ref origin/main)"
assert_eq "case 4: no layer sets the verdict, so it is the default fail" \
  "loosened_check_verdict: fail (default)" "$(line_of "$out" loosened_check_verdict)"
assert_eq "case 4: no layer sets patterns, so the list is empty" \
  "loosened_check_patterns: [] (default)" "$(line_of "$out" loosened_check_patterns)"
out="$(node "$RESOLVE" --root "$R1" --verdict-option note)"
assert_contains "case 4: without --ref the repository layer is skipped and the head file is not read" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: note (userConfig)"
assert_contains "case 4: without --ref the skip is named" "$out" "INFO repository layer skipped"
printf '%s' '["test/**"]' >"$TEST_TMPDIR/patterns-c4"
out="$(node "$RESOLVE" --root "$R1" --ref origin/nope --verdict-option note --patterns-file "$TEST_TMPDIR/patterns-c4")"
assert_eq "case 4: an unreadable ref resolves fail over a user note, the safe floor" \
  "loosened_check_verdict: fail (unreadable default branch)" "$(line_of "$out" loosened_check_verdict)"
assert_eq "case 4: an unreadable ref keeps the user's patterns" \
  'loosened_check_patterns: ["test/**"] (userConfig)' "$(line_of "$out" loosened_check_patterns)"
assert_contains "case 4: an unreadable ref is named in a WARN line" "$out" "WARN origin/nope could not be read"
printf '%s' 'not json' >"$TEST_TMPDIR/patterns-c4-invalid"
out="$(node "$RESOLVE" --root "$R4" --ref origin/main --verdict-option sometimes --patterns-file "$TEST_TMPDIR/patterns-c4-invalid")"
assert_contains "case 4: an invalid user verdict is named" "$out" "WARN userConfig loosened_check_verdict"
assert_contains "case 4: an invalid user verdict falls back to fail" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: fail (default)"
assert_contains "case 4: an invalid user pattern list is named" "$out" "WARN userConfig loosened_check_patterns"

R5="$(new_repo c5 $'loosened_check_verdict: lenient\n')"
out="$(node "$SCRIPT_DIR/../skills/setup/scripts/setup-apply.mjs" --check --root "$R5")"
assert_eq "case 5: an unknown verdict fails the schema check" "1" "$?"
assert_contains "case 5: the WARN names the key and the value" "$out" "loosened_check_verdict=lenient"
out="$(node "$RESOLVE" --root "$R5" --ref origin/main)"
assert_contains "case 5: an invalid committed verdict resolves the default fail" \
  "$(line_of "$out" loosened_check_verdict)" "loosened_check_verdict: fail (default)"
R5B="$(new_repo c5b $'loosened_check_verdict: note\nloosened_check_patterns:\n  - "ci/**"\n')"
node "$SCRIPT_DIR/../skills/setup/scripts/setup-apply.mjs" --check --root "$R5B" >/dev/null
assert_eq "case 5: a valid file passes the schema check" "0" "$?"

S1="$TEST_TMPDIR/ran-dollar-paren"
S2="$TEST_TMPDIR/ran-backtick"
P6="$TEST_TMPDIR/patterns-c6"
# shellcheck disable=SC2016 # the quote, $(...) and backtick are the literal input under test
printf '["text:it'\''s $(touch %s) `touch %s`"]' "$S1" "$S2" >"$P6"
expected6="loosened_check_patterns: [\"text:it's \$(touch $S1) \`touch $S2\`\"] (userConfig)"
out="$(node "$RESOLVE" --root "$R4" --ref origin/main --patterns-file "$P6")"
assert_eq "case 6: a pattern holding a quote, \$(...) and a backtick reaches the resolver intact" \
  "$expected6" "$(line_of "$out" loosened_check_patterns)"
assert_eq "case 6: the \$(...) in the pattern never ran" "absent" "$([[ -e "$S1" ]] && echo present || echo absent)"
assert_eq "case 6: the backtick in the pattern never ran" "absent" "$([[ -e "$S2" ]] && echo present || echo absent)"
# shellcheck disable=SC2016 # the literal, unexpanded placeholder is the input under test
printf '%s' '${user_config.loosened_check_patterns}' >"$TEST_TMPDIR/patterns-c6-unset"
out="$(node "$RESOLVE" --root "$R4" --ref origin/main --patterns-file "$TEST_TMPDIR/patterns-c6-unset")"
assert_eq "case 6: a file holding the unrendered placeholder is unset" \
  "loosened_check_patterns: [] (default)" "$(line_of "$out" loosened_check_patterns)"
: >"$TEST_TMPDIR/patterns-c6-empty"
out="$(node "$RESOLVE" --root "$R4" --ref origin/main --patterns-file "$TEST_TMPDIR/patterns-c6-empty")"
assert_eq "case 6: an empty file is unset" \
  "loosened_check_patterns: [] (default)" "$(line_of "$out" loosened_check_patterns)"
node "$RESOLVE" --root "$R4" --ref origin/main --patterns-file "$TEST_TMPDIR/no-such-file" >/dev/null 2>&1
assert_eq "case 6: an unreadable patterns file is a usage error" "2" "$?"
node "$RESOLVE" --root "$R4" --ref origin/main --patterns-option '["test/**"]' >/dev/null 2>&1
assert_eq "case 6: the shell-argument form is gone" "2" "$?"

FAKE_BIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # the stub's own variables expand when it runs, not here
printf '#!/usr/bin/env bash\n[[ "$1 $2" == "api repos/{owner}/{repo}/issues/$FAKE_GH_ISSUE" ]] || exit 1\n[[ -n "${FAKE_GH_REPLY:-}" ]] || { echo "HTTP 404" >&2; exit 1; }\nprintf "%%s" "$FAKE_GH_REPLY"\n' >"$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/gh"
TRUST_LIST='{"version": 1, "actors": [{"id": 101, "login": "owner-person", "kind": "human"}, {"id": 202, "login": "lanes[bot]", "kind": "bot"}]}'
R7="$TEST_TMPDIR/c7"
mkdir -p "$R7/.github/standards/trusted-actors"
g "$R7" init -q
printf '%s' "$TRUST_LIST" >"$R7/.github/standards/trusted-actors/trusted-actors.json"
g "$R7" add .github
g "$R7" commit -q -m base
g "$R7" update-ref refs/remotes/origin/main HEAD
g "$R7" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
spec_line() { (cd "$R7" && PATH="$FAKE_BIN:$PATH" FAKE_GH_ISSUE=42 FAKE_GH_REPLY="$1" node "$RESOLVE" --root "$R7" "${@:2}" | grep '^loosened_check_spec: '); }
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref origin/main --spec-issue 42)"
assert_contains "case 7: a trusted human's issue gives the spec's reason" "$out" "loosened_check_spec: counts"
out="$(spec_line '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}' --ref origin/main --spec-issue 42)"
assert_contains "case 7: an author off the list gives no reason" "$out" "loosened_check_spec: no reason"
out="$(spec_line '{"number": 42, "user": {"login": "lanes[bot]", "id": 202, "type": "Bot"}}' --ref origin/main --spec-issue 42)"
assert_contains "case 7: a listed bot is not a person, so no reason" "$out" "loosened_check_spec: no reason"
out="$(spec_line '' --ref origin/main --spec-issue 42)"
assert_contains "case 7: an author gh cannot read gives no reason" "$out" "loosened_check_spec: no reason"
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref origin/nope --spec-issue 42)"
assert_contains "case 7: a trusted-actor list that cannot be read gives no reason" "$out" "loosened_check_spec: no reason"
printf '%s' '{"version": 1, "actors": [{"id": 999, "login": "stranger", "kind": "human"}]}' >"$R7/.github/standards/trusted-actors/trusted-actors.json"
out="$(spec_line '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}' --ref origin/main --spec-issue 42)"
assert_contains "case 7: a head that adds the author to its own list gives no reason" "$out" "loosened_check_spec: no reason"
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref origin/main)"
assert_contains "case 7: with no --spec-issue the spec gives no reason" "$out" "loosened_check_spec: no reason"
node "$RESOLVE" --root "$R7" --ref origin/main --spec-issue '42; rm' >/dev/null 2>&1
assert_eq "case 7: a --spec-issue that is not a number is a usage error" "2" "$?"

g "$R7" checkout -q -b head-branch
g "$R7" commit -q -a -m "head adds stranger"
g "$R7" update-ref refs/remotes/origin/head-branch HEAD
out="$(spec_line '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}' --ref origin/head-branch --spec-issue 42)"
assert_contains "case 7b: a head-branch --ref whose list adds the author is refused" "$out" "loosened_check_spec: no reason"
assert_contains "case 7b: the refusal names the default branch" "$out" "--ref origin/head-branch is not the default branch origin/main"
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref origin/head-branch --spec-issue 42)"
assert_contains "case 7b: a head-branch --ref is refused even for an author the default branch trusts" "$out" "loosened_check_spec: no reason"
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref "$(g "$R7" rev-parse origin/main)" --spec-issue 42)"
assert_contains "case 7b: a --ref naming the default branch's commit is read" "$out" "loosened_check_spec: counts"
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --spec-issue 42)"
assert_contains "case 7b: with no --ref the resolved default branch is read" "$out" "loosened_check_spec: counts (issue #42 by owner-person, id 101, a trusted person at origin/main)"
g "$R7" symbolic-ref -d refs/remotes/origin/HEAD
out="$(spec_line '{"number": 42, "user": {"login": "owner-person", "id": 101, "type": "User"}}' --ref origin/main --spec-issue 42)"
assert_contains "case 7b: a default branch that cannot be resolved gives no reason" "$out" "loosened_check_spec: no reason (the default branch could not be resolved)"

STD_FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"
STD_SHA="$(jq -r .object.sha "$STD_FIX/standards-ref-heads-main.json")"
STD_HUMAN="$(jq -r '[.actors[] | select(.kind == "human")][0].id' "$STD_FIX/standards-trusted-actors.json")"
STD_BIN="$TEST_TMPDIR/std-bin"
mkdir -p "$STD_BIN"
# shellcheck disable=SC2016 # the stub's own variables expand when it runs, not here
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$FAKE_GH_CALLS"\ncase "$*" in\n"api repos/{owner}/{repo}/issues/$FAKE_GH_ISSUE") printf "%%s" "$FAKE_GH_REPLY" ;;\n"api repos/acme/standards/git/ref/heads/main --jq .object.sha") [[ -f "${FAKE_STD_COMMIT:-}" ]] || exit 1; jq -r .object.sha "$FAKE_STD_COMMIT" ;;\n"api repos/acme/standards/commits/main --jq .sha") printf "%%s\\n" ffffffffffffffffffffffffffffffffffffffff ;;\n"api -H Accept: application/vnd.github.raw repos/acme/standards/contents/components/trusted-actors/trusted-actors.json?ref=$FAKE_STD_SHA") cat "$FAKE_STD_LIST" ;;\n*) exit 1 ;;\nesac\n' >"$STD_BIN/gh"
chmod +x "$STD_BIN/gh"
R7S="$(new_repo c7s $'fanout_diversity: lens\n')"
mkdir -p "$R7S/.github/standards/trusted-actors"
printf '%s' '{"version": 1, "actors": [{"id": 999, "login": "stranger", "kind": "human"}]}' >"$R7S/.github/standards/trusted-actors/trusted-actors.json"
printf 'pr_open_state: ready\ntrusted_actors_source: standards\nstandards_repository: acme/standards\n' >"$R7S/docs/conventions/source-control.yaml"
g "$R7S" add .github docs
g "$R7S" commit -q -m "opt in"
g "$R7S" update-ref refs/remotes/origin/main HEAD
std_at() { (cd "$R7S" && PATH="$STD_BIN:$PATH" FAKE_GH_CALLS="$TEST_TMPDIR/std-calls" FAKE_GH_ISSUE=42 FAKE_GH_REPLY="$1" FAKE_STD_COMMIT="${2-$STD_FIX/standards-ref-heads-main.json}" FAKE_STD_SHA="$STD_SHA" FAKE_STD_LIST="$STD_FIX/standards-trusted-actors.json" node "$RESOLVE" --root "$R7S" --ref origin/main --spec-issue 42 | grep '^loosened_check_spec: '); }
: >"$TEST_TMPDIR/std-calls"
out="$(std_at "{\"number\": 42, \"user\": {\"login\": \"owner-person\", \"id\": $STD_HUMAN, \"type\": \"User\"}}")"
assert_contains "case 7c: opted in, a person on the standards list counts" "$out" "loosened_check_spec: counts (issue #42 by owner-person, id $STD_HUMAN, a trusted person at acme/standards@$STD_SHA)"
assert_eq "case 7c: standards main is resolved once, by its full ref" "1" "$(grep -c 'standards/git/ref/heads/main' "$TEST_TMPDIR/std-calls")"
assert_eq "case 7c: never commits/main, which a tag named main answers" "0" "$(grep -c 'standards/commits/' "$TEST_TMPDIR/std-calls")"
out="$(std_at '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}')"
assert_contains "case 7c: opted in, the repository's copy is not read" "$out" "loosened_check_spec: no reason"
out="$(std_at "{\"number\": 42, \"user\": {\"login\": \"owner-person\", \"id\": $STD_HUMAN, \"type\": \"User\"}}" "$TEST_TMPDIR/no-such-commit.json")"
assert_contains "case 7c: standards main unresolved gives no reason" "$out" "loosened_check_spec: no reason (acme/standards main could not be resolved)"
for bad in '' 'standards_repository: not a repo\n' 'standards_repository: [acme/standards]\n'; do
  printf 'trusted_actors_source: standards\n%b' "$bad" >"$R7S/docs/conventions/source-control.yaml"
  g "$R7S" commit -q -a -m "standards repository: ${bad:-none}"
  g "$R7S" update-ref refs/remotes/origin/main HEAD
  : >"$TEST_TMPDIR/std-calls"
  out="$(std_at "{\"number\": 42, \"user\": {\"login\": \"owner-person\", \"id\": $STD_HUMAN, \"type\": \"User\"}}")"
  assert_contains "case 7c: standards with standards_repository '${bad:-unset}' gives no reason" "$out" "trusted_actors_source standards needs standards_repository as <owner>/<repo>"
  assert_eq "case 7c: standards_repository '${bad:-unset}' makes no standards read" "0" "$(grep -c heads/main "$TEST_TMPDIR/std-calls")"
done
printf 'trusted_actors_source: repository\n' >"$R7S/docs/conventions/source-control.yaml"
g "$R7S" commit -q -a -m "copy source"
g "$R7S" update-ref refs/remotes/origin/main HEAD
: >"$TEST_TMPDIR/std-calls"
out="$(std_at '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}')"
assert_contains "case 7c: trusted_actors_source repository reads the copy" "$out" "loosened_check_spec: counts"
assert_eq "case 7c: the copy source makes no standards read" "0" "$(grep -c standards/ "$TEST_TMPDIR/std-calls")"
printf 'trusted_actors_source: elsewhere\n' >"$R7S/docs/conventions/source-control.yaml"
g "$R7S" commit -q -a -m "unknown source"
g "$R7S" update-ref refs/remotes/origin/main HEAD
out="$(std_at '{"number": 42, "user": {"login": "stranger", "id": 999, "type": "User"}}')"
assert_contains "case 7c: an unknown trusted_actors_source gives no reason" "$out" 'trusted_actors_source "elsewhere" is not one of repository, standards'

spec_at() { (cd "$1" && PATH="$FAKE_BIN:$PATH" FAKE_GH_ISSUE=42 FAKE_GH_REPLY="$2" node "$RESOLVE" --root "$1" --ref origin/main --spec-issue 42 | grep '^loosened_check_spec: '); }
out="$(spec_at "$R4" '{"number": 42, "author_association": "MEMBER", "user": {"login": "member", "id": 7, "type": "User"}}')"
assert_contains "case 8: no list and a MEMBER human counts" "$out" "loosened_check_spec: counts"
assert_contains "case 8: the rule that decided is named" "$out" "author_association MEMBER, no trusted-actor list at origin/main"
for assoc in OWNER COLLABORATOR; do
  out="$(spec_at "$R4" "{\"number\": 42, \"author_association\": \"$assoc\", \"user\": {\"login\": \"p\", \"id\": 7, \"type\": \"User\"}}")"
  assert_contains "case 8: no list and an $assoc human counts" "$out" "loosened_check_spec: counts"
done
for assoc in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR; do
  out="$(spec_at "$R4" "{\"number\": 42, \"author_association\": \"$assoc\", \"user\": {\"login\": \"p\", \"id\": 7, \"type\": \"User\"}}")"
  assert_contains "case 8: no list and $assoc gives no reason" "$out" "loosened_check_spec: no reason"
done
out="$(spec_at "$R4" '{"number": 42, "user": {"login": "p", "id": 7, "type": "User"}}')"
assert_contains "case 8: no list and no author_association gives no reason" "$out" "loosened_check_spec: no reason"
out="$(spec_at "$R4" '{"number": 42, "author_association": "MEMBER", "user": {"login": "lanes[bot]", "id": 202, "type": "Bot"}}')"
assert_contains "case 8: no list and a MEMBER bot gives no reason" "$out" "loosened_check_spec: no reason"
R8="$(new_repo c8 $'fanout_diversity: lens\n')"
mkdir -p "$R8/.github/standards/trusted-actors"
printf '%s' "$TRUST_LIST" >"$R8/.github/standards/trusted-actors/trusted-actors.json"
g "$R8" add .github
g "$R8" commit -q -m list
g "$R8" update-ref refs/remotes/origin/main HEAD
out="$(spec_at "$R8" '{"number": 42, "author_association": "MEMBER", "user": {"login": "member", "id": 7, "type": "User"}}')"
assert_contains "case 8: a list that exists decides alone: an unlisted MEMBER gives no reason" "$out" "loosened_check_spec: no reason"
printf '{"version": 1, "actors": [' >"$R8/.github/standards/trusted-actors/trusted-actors.json"
g "$R8" commit -q -a -m broken
g "$R8" update-ref refs/remotes/origin/main HEAD
out="$(spec_at "$R8" '{"number": 42, "author_association": "MEMBER", "user": {"login": "owner-person", "id": 101, "type": "User"}}')"
assert_contains "case 8: a list that cannot be parsed gives no reason, never the fallback" "$out" "loosened_check_spec: no reason"

RECORD_URL="https://records.example.com/decisions/blob/"
R9="$(new_repo c9 "loosened_check_decision_record: $RECORD_URL"$'\n')"
out="$(node "$RESOLVE" --root "$R9" --ref origin/main)"
assert_eq "case 9: a committed record prints its URL, trailing slash included, and its layer" \
  "loosened_check_decision_record: $RECORD_URL (docs/conventions/review.yaml)" "$(line_of "$out" loosened_check_decision_record)"
R9Q="$(new_repo c9q "loosened_check_decision_record: \"$RECORD_URL\""$'\n')"
out="$(node "$RESOLVE" --root "$R9Q" --ref origin/main)"
assert_eq "case 9: a quoted record prints the same URL" \
  "loosened_check_decision_record: $RECORD_URL (docs/conventions/review.yaml)" "$(line_of "$out" loosened_check_decision_record)"
printf 'fanout_diversity: lens\n' >"$R9/docs/conventions/review.yaml"
g "$R9" commit -q -a -m "head drops the record"
out="$(node "$RESOLVE" --root "$R9" --ref origin/main)"
assert_eq "case 9: a head that drops the record does not switch it off" \
  "loosened_check_decision_record: $RECORD_URL (docs/conventions/review.yaml)" "$(line_of "$out" loosened_check_decision_record)"
R9H="$(new_repo c9h $'fanout_diversity: lens\n')"
printf 'loosened_check_decision_record: %s\n' "$RECORD_URL" >"$R9H/docs/conventions/review.yaml"
g "$R9H" commit -q -a -m "head adds a record"
out="$(node "$RESOLVE" --root "$R9H" --ref origin/main)"
assert_eq "case 9: a record only the head adds is not read" \
  "loosened_check_decision_record: unset (default)" "$(line_of "$out" loosened_check_decision_record)"

out="$(node "$RESOLVE" --root "$R4" --ref origin/main)"
assert_eq "case 10: a file without the key leaves the record unset" \
  "loosened_check_decision_record: unset (default)" "$(line_of "$out" loosened_check_decision_record)"
R10A="$TEST_TMPDIR/c10a"
mkdir -p "$R10A"
g "$R10A" init -q
g "$R10A" commit -q --allow-empty -m base
g "$R10A" update-ref refs/remotes/origin/main HEAD
out="$(node "$RESOLVE" --root "$R10A" --ref origin/main)"
assert_eq "case 10: a default branch with no settings file leaves the record unset" \
  "loosened_check_decision_record: unset (default)" "$(line_of "$out" loosened_check_decision_record)"
for bad in "http://records.example.com/decisions/" "https://records.example.com/decisions" \
  "https://records.example.com/a/../b/" "records.example.com/decisions/" "" '""' "42" "true" "null" \
  "[https://records.example.com/decisions/]"; do
  R10="$(new_repo "c10-$((CASE_NUM))" "loosened_check_decision_record: $bad"$'\n')"
  out="$(node "$RESOLVE" --root "$R10" --ref origin/main)"
  assert_eq "case 10: the invalid value '$bad' resolves unreadable, never unset" \
    "loosened_check_decision_record: unreadable (invalid value in docs/conventions/review.yaml)" "$(line_of "$out" loosened_check_decision_record)"
  assert_contains "case 10: the invalid value '$bad' is named in a WARN line" "$out" "loosened_check_decision_record is invalid"
done
R10M="$(new_repo c10m $'loosened_check_decision_record: {url: https://records.example.com/decisions/}\n')"
out="$(node "$RESOLVE" --root "$R10M" --ref origin/main)"
assert_eq "case 10: a flow map, which the reader cannot parse, resolves unreadable, never unset" \
  "loosened_check_decision_record: unreadable (docs/conventions/review.yaml could not be parsed)" "$(line_of "$out" loosened_check_decision_record)"
R10L="$(new_repo c10l $'loosened_check_decision_record:\n  - https://records.example.com/decisions/\n')"
out="$(node "$RESOLVE" --root "$R10L" --ref origin/main)"
assert_eq "case 10: a block list resolves unreadable, never unset" \
  "loosened_check_decision_record: unreadable (invalid value in docs/conventions/review.yaml)" "$(line_of "$out" loosened_check_decision_record)"
out="$(node "$RESOLVE" --root "$R1" --ref origin/nope)"
assert_eq "case 10: an unreadable ref prints the distinct value" \
  "loosened_check_decision_record: unreadable (unreadable default branch)" "$(line_of "$out" loosened_check_decision_record)"
assert_contains "case 10: an unreadable ref's WARN says no spec can allow a loosening" "$out" "no spec can allow a loosening on this run"
out="$(node "$RESOLVE" --root "$R1")"
assert_eq "case 10: without --ref the record is unreadable, never unset" \
  "loosened_check_decision_record: unreadable (no --ref names the default branch)" "$(line_of "$out" loosened_check_decision_record)"
assert_contains "case 10: without --ref a WARN names the record" "$out" "WARN loosened_check_decision_record resolves unreadable"
R10P="$(new_repo c10p $'loosened_check_decision_record: [unclosed\n  bad: : yaml\n')"
out="$(node "$RESOLVE" --root "$R10P" --ref origin/main)"
assert_contains "case 10: a committed file that does not parse makes the record unreadable" \
  "$(line_of "$out" loosened_check_decision_record)" "loosened_check_decision_record: unreadable ("

node "$RESOLVE" --root "$R4" --ref origin/main --decision-record-option "$RECORD_URL" >/dev/null 2>&1
assert_eq "case 11: the resolver takes no user option for the record" "2" "$?"
manifest="$SCRIPT_DIR/../.claude-plugin/plugin.json"
assert_eq "case 11: the plugin declares no userConfig option for the record" "0" \
  "$(grep -c '"loosened_check_decision_record"' "$manifest")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
