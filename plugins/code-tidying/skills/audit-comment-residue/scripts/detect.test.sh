#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib — ships with the
# plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# --- Fixtures (built inline; no shipped fixture files) ---------------------------

ALL_SHAPES="$TEST_TMPDIR/all-shapes.py"
cat >"$ALL_SHAPES" <<'EOF'
# used to buffer writes; now flushes immediately
result = run()  # as you asked, retry three times
parse()  # Task 2 replaces the old tokenizer
# see PR #45 for the original rationale
EOF

CLEAN="$TEST_TMPDIR/clean.py"
cat >"$CLEAN" <<'EOF'
# Computes the checksum over the payload.
previously = load_cache()
total = a + b  # add the operands
digest = hashn()  # encode as UTF-8 and take the SHA-256 digest
# TODO(#123): tighten the upper bound
EOF

# String-aware comment extraction: a comment leader inside a string literal is not a comment,
# but a real leader after a closed string still is, and apostrophes in comment prose must not
# swallow the comment.
STRINGS="$TEST_TMPDIR/strings.js"
cat >"$STRINGS" <<'EOF'
const url = "https://example.com/used to do X; now does Y";
const s = "text";  // used to return null
// it's no longer used
EOF

# Bare hyphenated tracker key (advertised JIRA-123 form) is ticket-pr-residue.
TICKET="$TEST_TMPDIR/ticket.js"
cat >"$TICKET" <<'EOF'
// JIRA-123 tracks the original design
EOF

OPTOUT="$TEST_TMPDIR/optout.py"
cat >"$OPTOUT" <<'EOF'
flush()  # Task 9 in the plan replaces the old flush
# comment-residue-ignore
# used to do X, now does Y
value = 1  # per your request  # comment-residue-ignore
EOF

# --- 1. --help / unknown-arg contract ---------------------------------------------

help_exit=0
bash "$DETECT" --help >/dev/null 2>&1 || help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"

unknown_exit=0
bash "$DETECT" --bogus >/dev/null 2>&1 || unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"

# --- 2. All residue shapes detected, with tiers ------------------------------------

out="$(bash "$DETECT" "$ALL_SHAPES")"
assert_contains "history-narration finding" "$out" "Finding shape: history-narration"
assert_contains "conversational-antecedent finding" "$out" "Finding shape: conversational-antecedent"
assert_contains "plan-reference finding" "$out" "Finding shape: plan-reference"
assert_contains "ticket-pr-residue finding" "$out" "Finding shape: ticket-pr-residue"
assert_contains "ticket-pr-residue is tier 2" "$out" "Finding tier: 2"
assert_contains "file summary present" "$out" "Summary file: $ALL_SHAPES"

# --- 3. Clean fixture: code words, hex, encodings, sanctioned TODO not flagged ------

clean_out="$(bash "$DETECT" "$CLEAN")"
assert_contains "clean summary present" "$clean_out" "Summary total:"
assert_not_contains "code identifier 'previously' (no comment) not flagged" "$clean_out" "Finding shape: history-narration"
assert_not_contains "UTF-8 / SHA-256 not a ticket ref" "$clean_out" "Finding shape: ticket-pr-residue"
assert_not_contains "sanctioned TODO(#123) not flagged" "$clean_out" "Finding line: 5"

# --- 3b. String-aware extraction: leader inside a string is not a comment -------------

strings_out="$(bash "$DETECT" "$STRINGS")"
assert_not_contains "residue words inside a quoted URL are not flagged" "$strings_out" "Finding line: 1"
assert_contains "real comment after a closed string is still flagged" "$strings_out" "Finding line: 2"
assert_contains "apostrophe in comment prose does not suppress residue" "$strings_out" "Finding line: 3"

# --- 3c. Bare hyphenated tracker key (JIRA-123) is ticket-pr-residue -------------------

ticket_out="$(bash "$DETECT" "$TICKET")"
assert_contains "bare JIRA-123 key detected" "$ticket_out" "Finding shape: ticket-pr-residue"

# --- 4. Opt-out markers suppress wrapped content; control still detected -------------

opt_out="$(bash "$DETECT" "$OPTOUT")"
assert_contains "control residue still detected" "$opt_out" "Finding shape: plan-reference"
assert_not_contains "opt-out history suppressed" "$opt_out" "used to do x"
assert_not_contains "opt-out inline-line suppressed" "$opt_out" "Finding shape: conversational-antecedent"

# --- 5. Markdown target skipped (audit-noise's territory) -----------------------------

MD_FIXTURE="$TEST_TMPDIR/notes.md"
cat >"$MD_FIXTURE" <<'EOF'
used to do X, now does Y — per your request.
EOF
md_out="$(bash "$DETECT" "$MD_FIXTURE")"
assert_contains "markdown target yields no code files" "$md_out" "files=0"

# --- 6. Directory target expands to its code files ----------------------------------

DIR_FIXTURE="$TEST_TMPDIR/dir-target/nested"
mkdir -p "$DIR_FIXTURE"
cp "$ALL_SHAPES" "$DIR_FIXTURE/inner.py"
dir_out="$(bash "$DETECT" "$TEST_TMPDIR/dir-target")"
assert_contains "directory target audits nested code file" "$dir_out" "Summary file: $DIR_FIXTURE/inner.py"
assert_contains "directory target finds shapes" "$dir_out" "Finding shape: history-narration"

# --- 7. --paths-file input ----------------------------------------------------------

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$CLEAN" >"$PATHS"
pf_out="$(bash "$DETECT" --paths-file "$PATHS")"
assert_contains "paths-file target audited" "$pf_out" "Summary file: $CLEAN"

# --paths-file with no value must fail fast (exit 2), not spin the arg loop forever.
missing_val_exit=0
timeout 10 bash "$DETECT" --paths-file >/dev/null 2>&1 || missing_val_exit=$?
assert_exit "--paths-file with missing value exits 2" 2 "$missing_val_exit"

# --- 8. Relative targets stay anchored to the caller cwd, not the repo root -----------
# Invoked from a repo SUBDIRECTORY with a relative target (or relative --paths-file), the audit
# must still find the file — it cd's to the repo root internally, so unanchored relatives miss.
# The invocation dir must live inside a git repo for repo_root to differ from the caller cwd.
REPO8="$TEST_TMPDIR/repo8"
SUBDIR="$REPO8/sub/nested"
mkdir -p "$SUBDIR"
git -C "$REPO8" init -q
cp "$ALL_SHAPES" "$SUBDIR/rel.py"
rel_out="$(cd "$SUBDIR" && bash "$DETECT" rel.py)"
assert_contains "relative target audited from subdir cwd" "$rel_out" "Finding shape: history-narration"
assert_not_contains "relative target is not reported as files=0" "$rel_out" "files=0"

printf '%s\n' "rel.py" >"$SUBDIR/rel-paths.txt"
relpf_out="$(cd "$SUBDIR" && bash "$DETECT" --paths-file rel-paths.txt)"
assert_contains "relative --paths-file target audited from subdir cwd" "$relpf_out" "Finding shape: history-narration"

# --- 9. Default-target discovery parses porcelain, not whitespace fields (#3126) --------
# With no arguments the audit discovers targets from `git status --porcelain`. A path
# containing a space arrives C-quoted ("my helper.sh"); splitting on whitespace kept the
# closing quote and dropped everything before the space, so the file resolved to nothing and
# vanished from the run — reported as a reassuring files=0 rather than as an error. A plain
# path passes either implementation, so the fixture name must contain a space.

# The two arms live in separate repos on purpose: sharing one would let a correctly-parsed
# file keep the run's files= count above zero and mask the other arm's disappearance.

# 9a. Spaced path is the whole tree — the broken parse reports the misleading files=0.
REPO9="$TEST_TMPDIR/repo9"
mkdir -p "$REPO9"
git -C "$REPO9" init -q
cp "$ALL_SHAPES" "$REPO9/my helper.py"

spaced_out="$(cd "$REPO9" && bash "$DETECT")"
assert_not_contains "spaced default target is not reported as files=0" "$spaced_out" "files=0"
assert_not_contains "spaced default target does not claim a clean tree" "$spaced_out" "no code targets"
assert_contains "spaced default target audited" "$spaced_out" "Summary file: my helper.py"
assert_contains "spaced default target finds shapes" "$spaced_out" "Finding shape: history-narration"

# 9b. Rename arm: porcelain emits "old -> new"; the new path is the one to audit.
REPO10="$TEST_TMPDIR/repo10"
mkdir -p "$REPO10"
git -C "$REPO10" init -q
cp "$ALL_SHAPES" "$REPO10/original.py"
git -C "$REPO10" add original.py
git -C "$REPO10" -c user.email=t@example.com -c user.name=t commit -qm init
git -C "$REPO10" mv original.py renamed.py

rename_out="$(cd "$REPO10" && bash "$DETECT")"
assert_contains "renamed default target resolves to the new path" "$rename_out" "Summary file: renamed.py"
assert_not_contains "renamed default target does not audit the old path" "$rename_out" "Summary file: original.py"

# 9c. A spaced path that is ALSO renamed exercises quote-stripping and the " -> " split
# together — the combination the two arms above each cover only half of.
REPO11="$TEST_TMPDIR/repo11"
mkdir -p "$REPO11"
git -C "$REPO11" init -q
cp "$ALL_SHAPES" "$REPO11/old name.py"
git -C "$REPO11" add "old name.py"
git -C "$REPO11" -c user.email=t@example.com -c user.name=t commit -qm init
git -C "$REPO11" mv "old name.py" "new name.py"

spaced_rename_out="$(cd "$REPO11" && bash "$DETECT")"
assert_not_contains "spaced rename is not reported as files=0" "$spaced_rename_out" "files=0"
assert_contains "spaced rename resolves to the new path" "$spaced_rename_out" "Summary file: new name.py"

# 9d. Porcelain is XY: X is the index status, Y the worktree status, and a rename can be
# recorded in EITHER. An intent-to-add rename (`mv old new && git add -N new`) emits
# " R old -> new" — the R is in Y, with X blank. Gating the arrow-split on X alone left
# the record unsplit, so the whole "old -> new" string became the path and resolved to
# nothing. Regression guard for that half of the rename case.
REPO12="$TEST_TMPDIR/repo12"
mkdir -p "$REPO12"
git -C "$REPO12" init -q
cp "$ALL_SHAPES" "$REPO12/old.py"
git -C "$REPO12" add old.py
git -C "$REPO12" -c user.email=t@example.com -c user.name=t commit -qm init
mv "$REPO12/old.py" "$REPO12/new.py"
git -C "$REPO12" add -N new.py

worktree_rename_out="$(cd "$REPO12" && bash "$DETECT")"
assert_not_contains "worktree-column rename is not reported as files=0" "$worktree_rename_out" "files=0"
assert_contains "worktree-column rename resolves to the new path" "$worktree_rename_out" "Summary file: new.py"

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
