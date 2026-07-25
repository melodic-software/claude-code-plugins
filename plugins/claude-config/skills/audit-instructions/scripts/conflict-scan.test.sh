#!/usr/bin/env bash
# Regression tests for conflict-scan.sh (self-contained — ships with the plugin).
# The must-not-flag cases are the point of this suite: false positives are the
# failure mode for a conflict detector, so each suppression rule is pinned here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/conflict-scan.sh"

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
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "unexpected substring: $3" ;;
    *) pass "$1" ;;
  esac
}

if ! command -v grep >/dev/null 2>&1; then
  echo "SKIP: grep not installed" >&2
  exit 0
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "SKIP: awk not installed" >&2
  exit 0
fi

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: the worked example — mandate vs prohibition across two files ----
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

# --- Case 3 (MUST NOT FLAG): same-file pair is not cross-surface -------------
# The repo's sharpest false positive: a self-arbitrating absolute sitting beside
# a directive that presupposes exactly its exception, both in one file.
SAMEFILE="$TEST_TMPDIR/same-file.md"
cat >"$SAMEFILE" <<'EOF'
When asking the user a question (inline or via AskUserQuestion), include your recommendation.
Ask questions inline; never use the AskUserQuestion tool unless explicitly asked to use it.
EOF
assert_eq "same-file mandate/prohibition pair not reported" "0" "$(bash "$SCRIPT" --count "$SAMEFILE")"

# --- Case 4 (MUST NOT FLAG): an explicit opt-in gate is arbitration ----------
GATED="$TEST_TMPDIR/gated.md"
cat >"$GATED" <<'EOF'
Render the round via `AskUserQuestion` only when the plugin's use_ask_user_question user config is on.
EOF
assert_eq "config-gated mandate suppressed against a prohibition" "0" \
  "$(bash "$SCRIPT" --count "$GATED" "$PROHIBIT")"

# --- Case 5 (MUST NOT FLAG): prohibition trailing the entity, different object
# "…via `AskUserQuestion` once … Do not gate per repo." The prohibition governs
# per-repo gating, not the tool. Whole-line matching reads this as a conflict.
TRAILING="$TEST_TMPDIR/trailing.md"
cat >"$TRAILING" <<'EOF'
Show the whole-batch plan, then `AskUserQuestion` once, then apply once. Do not gate per repo.
EOF
OUT=$(bash "$SCRIPT" "$TRAILING" "$MANDATE")
assert_not_contains "trailing prohibition about another object yields no pair" "$OUT" "|AskUserQuestion|"

# --- Case 6 (MUST NOT FLAG): distant prohibition about an unrelated object ----
DISTANT="$TEST_TMPDIR/distant.md"
cat >"$DISTANT" <<'EOF'
Branches checked out in a linked worktree: never offer them for deletion, and route the user to the worktree tool to clean up first; deletion is confirmed via `AskUserQuestion` per the cleanup context file.
EOF
OUT=$(bash "$SCRIPT" "$DISTANT" "$MANDATE")
assert_not_contains "distant prohibition does not flip the entity's polarity" "$OUT" "|AskUserQuestion|"

# --- Case 7 (MUST NOT FLAG): two surfaces that AGREE are not a conflict ------
AGREE="$TEST_TMPDIR/agree.md"
cat >"$AGREE" <<'EOF'
Use `AskUserQuestion` to confirm the destructive step before applying.
EOF
assert_eq "two mandates on one entity yield no pair" "0" "$(bash "$SCRIPT" --count "$AGREE" "$MANDATE")"

# --- Case 8 (MUST NOT FLAG): different entities are different observables ----
OTHER="$TEST_TMPDIR/other-entity.md"
cat >"$OTHER" <<'EOF'
Never use the WebFetch tool for authenticated URLs.
EOF
assert_eq "disagreement about a different entity yields no pair" "0" \
  "$(bash "$SCRIPT" --count "$OTHER" "$MANDATE")"

# --- Case 9 (MUST NOT FLAG): permissive language is not a mandate ------------
PERMISSIVE="$TEST_TMPDIR/permissive.md"
cat >"$PERMISSIVE" <<'EOF'
The user may override via `AskUserQuestion` only when they explicitly accept skipping the step.
EOF
assert_eq "permissive 'may override' is not a mandate" "0" \
  "$(bash "$SCRIPT" --count "$PERMISSIVE" "$PROHIBIT")"

# --- Case 10: clean input ----------------------------------------------------
CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
Run npm test before committing.
API handlers live in src/api/handlers/.
EOF
assert_contains "clean input message" "$(bash "$SCRIPT" "$CLEAN")" "No conflict candidates found."
assert_eq "clean input count is 0" "0" "$(bash "$SCRIPT" --count "$CLEAN")"

# --- Case 11: a single file can never produce a cross-surface pair -----------
assert_eq "one file alone yields no pair" "0" "$(bash "$SCRIPT" --count "$MANDATE")"

# --- Case 12: nonexistent path skipped, not an error ------------------------
rc=0
OUT=$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.md") || rc=$?
assert_exit "nonexistent path exits 0" 0 "$rc"
assert_contains "nonexistent path yields clean message" "$OUT" "No conflict candidates found."

# --- Case 13: no file arguments ---------------------------------------------
rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "no-args exits 0" 0 "$rc"
assert_eq "no-args count is 0" "0" "$(bash "$SCRIPT" --count)"

# --- Case 14: rows are de-duplicated ----------------------------------------
DUPE="$TEST_TMPDIR/dupe.md"
cat >"$DUPE" <<'EOF'
Mandatory: `AskUserQuestion` and again `AskUserQuestion` on one line.
EOF
assert_eq "repeated entity on one line yields one pair" "1" "$(bash "$SCRIPT" --count "$DUPE" "$PROHIBIT")"

# --- Case 15: window is configurable and narrowing it drops distant tokens ---
WIDE="$TEST_TMPDIR/wide.md"
cat >"$WIDE" <<'EOF'
Never do that thing over there for some other reason entirely, and separately confirm via `AskUserQuestion`.
EOF
assert_eq "a 5-char window drops the distant prohibition" "0" \
  "$(CONFLICT_SCAN_WINDOW=5 bash "$SCRIPT" --count "$WIDE" "$AGREE")"

# --- Case 17: postposed prohibition in the entity's OWN sentence is caught ---
# "X must not be used" puts the prohibition after the entity. Reading only the
# text before the mention misses it AND lets the mandate regex match "must",
# silently classifying a prohibition as a mandate.
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

# --- Case 18 (MUST NOT FLAG): postposed prohibition past a sentence break ----
# Case 5's shape must survive the postposed check: the prohibition sits after a
# full stop, so it governs a different object.
assert_not_contains "prohibition past a sentence break still yields no pair" \
  "$(bash "$SCRIPT" "$TRAILING" "$MANDATE")" "|AskUserQuestion|"

# --- Case 19: a backticked single-word tool is an entity ---------------------
# `Bash`, `Read`, `Edit` are single words and cannot match CamelCase.
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

# --- Case 20 (MUST NOT FLAG): a bare capitalized word is not an entity -------
# Requiring the backticks is what keeps sentence-initial words out.
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

# --- Case 21: a backticked and a bare mention of one tool pair together ------
BAREWEB="$TEST_TMPDIR/bare-web.md"
cat >"$BAREWEB" <<'EOF'
Never use WebFetch for authenticated URLs.
EOF
assert_contains "backtick-stripped entity pairs with a bare mention" \
  "$(bash "$SCRIPT" "$WEBMANDATE" "$BAREWEB")" "|WebFetch|"

# --- Case 22: "opt-in" as SUBJECT is not arbitration -------------------------
# Naming an opt-in is not being gated on one. Suppression now additionally
# requires a conditional marker.
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

# --- Case 23: a prohibition in the PRECEDING sentence must not win ----------
# The leading window is 60 chars, so an earlier unrelated prohibition on the
# same line used to cross the sentence break and classify the mandate as a
# prohibition — pairing it with a real prohibition then yielded nothing.
PRESENTENCE="$TEST_TMPDIR/pre-sentence.md"
cat >"$PRESENTENCE" <<'EOF'
Never delete branches. Always use `AskUserQuestion` before deleting a branch.
EOF
assert_eq "prohibition in the preceding sentence does not flip the mandate" "1" \
  "$(bash "$SCRIPT" --count "$PRESENTENCE" "$OPTSUBJECT")"

# --- Case 24 (MUST NOT FLAG): a same-sentence prohibition still wins ---------
# Case 23 must not cost the ordinary "never use X" reading.
SAMESENTENCE="$TEST_TMPDIR/same-sentence.md"
cat >"$SAMESENTENCE" <<'EOF'
Run the checks first. Never use `AskUserQuestion` in an autonomous loop.
EOF
assert_eq "same-sentence prohibition still classifies as a prohibition" "1" \
  "$(bash "$SCRIPT" --count "$OPTMANDATE" "$SAMESENTENCE")"

# --- Case 25: a dot inside a token is not a sentence boundary ---------------
# `.claude/rules` and `v2.1.219` are everywhere in this corpus. Cutting the
# window at a bare mark would drop the prohibition governing the entity.
DOTTED="$TEST_TMPDIR/dotted.md"
cat >"$DOTTED" <<'EOF'
Never read `.claude/rules` with `WebFetch` during an audit.
EOF
assert_contains "a dot inside a token does not truncate the window" \
  "$(bash "$SCRIPT" "$WEBMANDATE" "$DOTTED")" "|WebFetch|"

# --- Case 26: an opt-in gate in a neighbouring sentence must not suppress ---
# Both token classes appearing in the raw span is not arbitration; the gate has
# to govern the entity, which means sharing its sentence.
FARGATE="$TEST_TMPDIR/far-gate.md"
cat >"$FARGATE" <<'EOF'
Never use `AskUserQuestion`. Opt-in is enabled only when set.
EOF
assert_eq "an opt-in gate in the next sentence does not suppress" "1" \
  "$(bash "$SCRIPT" --count "$OPTMANDATE" "$FARGATE")"

# --- Case 27 (MUST NOT FLAG): a mandate in a neighbouring sentence ----------
# A neutral mention beside an unrelated mandate is not a directive about the
# entity, and pairing it inflates the review queue.
FARMANDATE="$TEST_TMPDIR/far-mandate.md"
cat >"$FARMANDATE" <<'EOF'
Always run tests. `AskUserQuestion` is documented here.
EOF
assert_eq "a mandate in the next sentence does not classify a neutral mention" "0" \
  "$(bash "$SCRIPT" --count "$FARMANDATE" "$OPTSUBJECT")"

# --- Case 16: missing grep exits 2 ------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" "$CLEAN" 2>&1) || rc=$?
assert_exit "exit 2 when grep missing" 2 "$rc"
assert_contains "grep required message" "$err_out" "grep required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
