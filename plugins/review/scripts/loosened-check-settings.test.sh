#!/usr/bin/env bash
# test-scope: plugins/review/schemas/review.schema.json plugins/review/skills/setup/scripts/setup-apply.mjs plugins/review/lib/setup-apply.mjs plugins/review/lib/yaml-subset.mjs
# Tests for loosened-check-settings.mjs. Expected values come from the level
# rules in reference/config.md: loosened_check_verdict is a policy floor (fail
# in any valid layer wins, default fail) and loosened_check_patterns is the
# union of every valid layer's entries; both read the repository value from the
# default branch, never the head.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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

# new_repo <name> <committed review.yaml body>: a repository whose
# origin/main commits the body.
new_repo() {
  local r="$TEST_TMPDIR/$1"
  mkdir -p "$r/docs/conventions"
  g "$r" init -q
  printf '%s' "$2" >"$r/docs/conventions/review.yaml"
  g "$r" add docs/conventions/review.yaml
  g "$r" commit -q -m base
  g "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$r"
}

# --- Case 1: the head drops a default-branch pattern and sets note over fail --
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

# --- Case 2: fail in any layer wins; note holds only when no layer says fail ---
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

# --- Case 3: patterns are the union of the user option and the repository -----
printf '%s' '["test/**", "ci/checks/**"]' >"$TEST_TMPDIR/patterns-c3"
out="$(node "$RESOLVE" --root "$R1" --ref origin/main --patterns-file "$TEST_TMPDIR/patterns-c3")"
assert_eq "case 3: user and repository patterns are unioned, each once" \
  'loosened_check_patterns: ["test/**","ci/checks/**","text:continue-on-error"] (userConfig, docs/conventions/review.yaml)' \
  "$(line_of "$out" loosened_check_patterns)"

# --- Case 4: defaults, and layers that cannot be read ---------------------------
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

# --- Case 5: the schema refuses an unknown verdict, accepts a valid file -------
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

# --- Case 6: the patterns option arrives through a file, never through a shell -
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

# --- Case 7: the spec gives a reason only when a trusted human wrote the issue --
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

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
