#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/conflict-scan.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v awk >/dev/null 2>&1; then
  echo "SKIP: awk not installed" >&2
  exit 0
fi

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

MANDATE="$TEST_TMPDIR/skill-body.md"
cat >"$MANDATE" <<'EOF'
Mandatory gate: show dry-run output, then `AskUserQuestion`, then apply.
EOF
PROHIBIT="$TEST_TMPDIR/user-claude.md"
cat >"$PROHIBIT" <<'EOF'
Ask questions inline; never use the AskUserQuestion tool unless explicitly asked to use it.
EOF
rc=0
OUT=$(bash "$SCRIPT" "$MANDATE" "$PROHIBIT") || rc=$?
assert_exit "conflict scan exits 0 (advisory)" 0 "$rc"
assert_contains "worked example pairs mandate with prohibition" "$OUT" \
  "$MANDATE:1|$PROHIBIT:1|AskUserQuestion"
assert_contains "prohibition side's exception clause is flagged, not dropped" "$OUT" "exception-B"
assert_eq "worked example yields exactly one pair" "1" "$(bash "$SCRIPT" --count "$MANDATE" "$PROHIBIT")"

SAMEFILE="$TEST_TMPDIR/same-file.md"
cat >"$SAMEFILE" <<'EOF'
When asking the user a question (inline or via AskUserQuestion), include your recommendation.
Ask questions inline; never use the AskUserQuestion tool unless explicitly asked to use it.
EOF
assert_eq "same-file mandate/prohibition pair not reported" "0" "$(bash "$SCRIPT" --count "$SAMEFILE")"

GATED="$TEST_TMPDIR/gated.md"
cat >"$GATED" <<'EOF'
Render the round via `AskUserQuestion` only when the plugin's use_ask_user_question user config is on.
EOF
assert_eq "config-gated mandate suppressed against a prohibition" "0" \
  "$(bash "$SCRIPT" --count "$GATED" "$PROHIBIT")"

TRAILING="$TEST_TMPDIR/trailing.md"
cat >"$TRAILING" <<'EOF'
Show the whole-batch plan, then `AskUserQuestion` once, then apply once. Do not gate per repo.
EOF
OUT=$(bash "$SCRIPT" "$TRAILING" "$MANDATE")
assert_not_contains "trailing prohibition about another object yields no pair" "$OUT" "|AskUserQuestion|"

DISTANT="$TEST_TMPDIR/distant.md"
cat >"$DISTANT" <<'EOF'
Branches checked out in a linked worktree: never offer them for deletion, and route the user to the worktree tool to clean up first; deletion is confirmed via `AskUserQuestion` per the cleanup context file.
EOF
OUT=$(bash "$SCRIPT" "$DISTANT" "$MANDATE")
assert_not_contains "distant prohibition does not flip the entity's polarity" "$OUT" "|AskUserQuestion|"

AGREE="$TEST_TMPDIR/agree.md"
cat >"$AGREE" <<'EOF'
Use `AskUserQuestion` to confirm the destructive step before applying.
EOF
assert_eq "two mandates on one entity yield no pair" "0" "$(bash "$SCRIPT" --count "$AGREE" "$MANDATE")"

OTHER="$TEST_TMPDIR/other-entity.md"
cat >"$OTHER" <<'EOF'
Never use the WebFetch tool for authenticated URLs.
EOF
assert_eq "disagreement about a different entity yields no pair" "0" \
  "$(bash "$SCRIPT" --count "$OTHER" "$MANDATE")"

PERMISSIVE="$TEST_TMPDIR/permissive.md"
cat >"$PERMISSIVE" <<'EOF'
The user may override via `AskUserQuestion` only when they explicitly accept skipping the step.
EOF
assert_eq "permissive 'may override' is not a mandate" "0" \
  "$(bash "$SCRIPT" --count "$PERMISSIVE" "$PROHIBIT")"

CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
Run npm test before committing.
API handlers live in src/api/handlers/.
EOF
assert_contains "clean input message" "$(bash "$SCRIPT" "$CLEAN")" "No conflict candidates found."
assert_eq "clean input count is 0" "0" "$(bash "$SCRIPT" --count "$CLEAN")"

assert_eq "one file alone yields no pair" "0" "$(bash "$SCRIPT" --count "$MANDATE")"

rc=0
OUT=$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.md") || rc=$?
assert_exit "nonexistent path exits 0" 0 "$rc"
assert_contains "nonexistent path yields clean message" "$OUT" "No conflict candidates found."

rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "no-args exits 0" 0 "$rc"
assert_eq "no-args count is 0" "0" "$(bash "$SCRIPT" --count)"

DUPE="$TEST_TMPDIR/dupe.md"
cat >"$DUPE" <<'EOF'
Mandatory: `AskUserQuestion` and again `AskUserQuestion` on one line.
EOF
assert_eq "repeated entity on one line yields one pair" "1" "$(bash "$SCRIPT" --count "$DUPE" "$PROHIBIT")"

WIDE="$TEST_TMPDIR/wide.md"
cat >"$WIDE" <<'EOF'
Never do that thing over there for some other reason entirely, and separately confirm via `AskUserQuestion`.
EOF
assert_eq "a 5-char window drops the distant prohibition" "0" \
  "$(CONFLICT_SCAN_WINDOW=5 bash "$SCRIPT" --count "$WIDE" "$AGREE")"

POSTPOSED="$TEST_TMPDIR/postposed.md"
cat >"$POSTPOSED" <<'EOF'
`WebFetch` must not be used for documentation lookups.
EOF
WEBMANDATE="$TEST_TMPDIR/web-mandate.md"
cat >"$WEBMANDATE" <<'EOF'
Always use `WebFetch` for documentation lookups.
EOF
assert_eq "postposed prohibition pairs with a mandate" "1" \
  "$(bash "$SCRIPT" --count "$WEBMANDATE" "$POSTPOSED")"

assert_not_contains "prohibition past a sentence break still yields no pair" \
  "$(bash "$SCRIPT" "$TRAILING" "$MANDATE")" "|AskUserQuestion|"

BASHNO="$TEST_TMPDIR/bash-no.md"
cat >"$BASHNO" <<'EOF'
Never use `Bash` for file edits.
EOF
BASHYES="$TEST_TMPDIR/bash-yes.md"
cat >"$BASHYES" <<'EOF'
Always use `Bash` for file edits.
EOF
OUT=$(bash "$SCRIPT" "$BASHYES" "$BASHNO")
assert_contains "backticked single-word tool is paired" "$OUT" "|Bash|"

BAREYES="$TEST_TMPDIR/bare-yes.md"
cat >"$BAREYES" <<'EOF'
Always run the suite before you commit.
EOF
BARENO="$TEST_TMPDIR/bare-no.md"
cat >"$BARENO" <<'EOF'
Never skip the suite before you commit.
EOF
assert_eq "bare capitalized words yield no pair" "0" \
  "$(bash "$SCRIPT" --count "$BAREYES" "$BARENO")"

BAREWEB="$TEST_TMPDIR/bare-web.md"
cat >"$BAREWEB" <<'EOF'
Never use WebFetch for authenticated URLs.
EOF
assert_contains "backtick-stripped entity pairs with a bare mention" \
  "$(bash "$SCRIPT" "$WEBMANDATE" "$BAREWEB")" "|WebFetch|"

OPTSUBJECT="$TEST_TMPDIR/opt-subject.md"
cat >"$OPTSUBJECT" <<'EOF'
Never use `AskUserQuestion` for opt-in prompts.
EOF
OPTMANDATE="$TEST_TMPDIR/opt-mandate.md"
cat >"$OPTMANDATE" <<'EOF'
Always use `AskUserQuestion` for every confirmation.
EOF
assert_eq "opt-in as subject is not suppressed" "1" \
  "$(bash "$SCRIPT" --count "$OPTMANDATE" "$OPTSUBJECT")"

PRESENTENCE="$TEST_TMPDIR/pre-sentence.md"
cat >"$PRESENTENCE" <<'EOF'
Never delete branches. Always use `AskUserQuestion` before deleting a branch.
EOF
assert_eq "prohibition in the preceding sentence does not flip the mandate" "1" \
  "$(bash "$SCRIPT" --count "$PRESENTENCE" "$OPTSUBJECT")"

SAMESENTENCE="$TEST_TMPDIR/same-sentence.md"
cat >"$SAMESENTENCE" <<'EOF'
Run the checks first. Never use `AskUserQuestion` in an autonomous loop.
EOF
assert_eq "same-sentence prohibition still classifies as a prohibition" "1" \
  "$(bash "$SCRIPT" --count "$OPTMANDATE" "$SAMESENTENCE")"

DOTTED="$TEST_TMPDIR/dotted.md"
cat >"$DOTTED" <<'EOF'
Never read `.claude/rules` with `WebFetch` during an audit.
EOF
assert_contains "a dot inside a token does not truncate the window" \
  "$(bash "$SCRIPT" "$WEBMANDATE" "$DOTTED")" "|WebFetch|"

FARGATE="$TEST_TMPDIR/far-gate.md"
cat >"$FARGATE" <<'EOF'
Never use `AskUserQuestion`. Opt-in is enabled only when set.
EOF
assert_eq "an opt-in gate in the next sentence does not suppress" "1" \
  "$(bash "$SCRIPT" --count "$OPTMANDATE" "$FARGATE")"

FARMANDATE="$TEST_TMPDIR/far-mandate.md"
cat >"$FARMANDATE" <<'EOF'
Always run tests. `AskUserQuestion` is documented here.
EOF
assert_eq "a mandate in the next sentence does not classify a neutral mention" "0" \
  "$(bash "$SCRIPT" --count "$FARMANDATE" "$OPTSUBJECT")"

TWOENT="$TEST_TMPDIR/two-entities.md"
cat >"$TWOENT" <<'EOF'
Always use `Read`, but never use `Bash` for file inspection.
EOF
READNO="$TEST_TMPDIR/read-no.md"
cat >"$READNO" <<'EOF'
Never use `Read` for file inspection.
EOF
assert_contains "a contrastive clause does not flip the earlier entity" \
  "$(bash "$SCRIPT" "$TWOENT" "$READNO")" "|Read|"

BASHYES2="$TEST_TMPDIR/bash-yes-2.md"
cat >"$BASHYES2" <<'EOF'
Always use `Bash` for file inspection.
EOF
assert_contains "the entity inside the contrastive clause is still prohibited" \
  "$(bash "$SCRIPT" "$BASHYES2" "$TWOENT")" "|Bash|"

assert_eq "an ordinary comma does not truncate the window" "1" \
  "$(bash "$SCRIPT" --count "$MANDATE" "$PROHIBIT")"

NOCOMMA="$TEST_TMPDIR/no-comma.md"
cat >"$NOCOMMA" <<'EOF'
Always use `Read` but never use `Bash` for file inspection.
EOF
assert_contains "an unpunctuated contrastive does not flip the earlier entity" "$(bash "$SCRIPT" "$NOCOMMA" "$READNO")" "|Read|"
assert_contains "the entity after an unpunctuated contrastive is still prohibited" "$(bash "$SCRIPT" "$BASHYES2" "$NOCOMMA")" "|Bash|"

TEMPORAL="$TEST_TMPDIR/temporal.md"
cat >"$TEMPORAL" <<'EOF'
Always use `WebFetch` while the offline flag is unset.
EOF
assert_eq "temporal 'while' does not split the clause" "1" "$(bash "$SCRIPT" --count "$TEMPORAL" "$POSTPOSED")"

COORDAND="$TEST_TMPDIR/coord-and.md"
cat >"$COORDAND" <<'EOF'
Always use `Read` and never use `Bash` for file inspection.
EOF
assert_contains "a coordinated prohibition does not flip the earlier entity" \
  "$(bash "$SCRIPT" "$COORDAND" "$READNO")" "|Read|"
assert_contains "the entity inside the coordinated clause is still prohibited" \
  "$(bash "$SCRIPT" "$BASHYES2" "$COORDAND")" "|Bash|"

COORDMIRROR="$TEST_TMPDIR/coord-mirror.md"
cat >"$COORDMIRROR" <<'EOF'
Never use `Bash` and always use `Read` for file inspection.
EOF
assert_contains "a coordinated mandate is not overtaken by the leading prohibition" \
  "$(bash "$SCRIPT" "$COORDMIRROR" "$READNO")" "|Read|"
assert_contains "the leading prohibition still classifies its own entity" \
  "$(bash "$SCRIPT" "$BASHYES2" "$COORDMIRROR")" "|Bash|"

COORDBARE="$TEST_TMPDIR/coord-bare-mandate.md"
cat >"$COORDBARE" <<'EOF'
Never use `Bash` and use `Read` for file inspection.
EOF
assert_contains "a bare-'use' coordinated mandate splits like 'always use'" \
  "$(bash "$SCRIPT" "$COORDBARE" "$READNO")" "|Read|"

COORDPRESENT="$TEST_TMPDIR/coord-present.md"
cat >"$COORDPRESENT" <<'EOF'
Never use `Bash` and present `Read` to the operator.
EOF
assert_contains "a coordinated 'present' splits like every other mandate token" \
  "$(bash "$SCRIPT" "$COORDPRESENT" "$READNO")" "|Read|"

BAREAND="$TEST_TMPDIR/bare-and.md"
cat >"$BAREAND" <<'EOF'
Never use `Bash` and `Grep` for file inspection.
EOF
GREPYES="$TEST_TMPDIR/grep-yes.md"
cat >"$GREPYES" <<'EOF'
Always use `Grep` for file inspection.
EOF
assert_contains "a bare 'and' does not strip the token governing the second object" \
  "$(bash "$SCRIPT" "$BAREAND" "$GREPYES")" "|Grep|"

real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" "$CLEAN" 2>&1) || rc=$?
assert_exit "exit 2 when a prerequisite is missing" 2 "$rc"
assert_contains "names the missing prerequisite" "$err_out" "awk required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
