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

# --- 10. SKILL.md pre-computed-context parser stays at parity with detect.sh (#3126) ----
# SKILL.md's `Uncommitted code files:` line re-implements the porcelain parse to preview
# targets to the model. A divergence there is a false negative on the same surface, so the
# program is EXTRACTED from SKILL.md and executed rather than being restated here — a copy
# would pass while the real line rotted. Fixture names force C-quoting through an embedded
# quote and backslash, not just a space, since quote-stripping alone passes a spaced name.

SKILL_MD="$SCRIPT_DIR/../SKILL.md"
if [[ ! -f "$SKILL_MD" ]]; then
  fail "SKILL.md located for parity check" "file at $SKILL_MD" "missing"
else
  # Pull the awk program out of: ... | awk '<program>' | grep ...
  skill_awk="$(sed -n "s/^Uncommitted code files:.*| awk '\(.*\)' | grep .*$/\1/p" "$SKILL_MD")"
  if [[ -z "$skill_awk" ]]; then
    fail "SKILL.md awk program extracted" "non-empty program" "no match — line shape changed"
  else
    pass "SKILL.md awk program extracted"

    REPO13="$TEST_TMPDIR/repo13"
    mkdir -p "$REPO13"
    git -C "$REPO13" init -q
    : >"$REPO13/quote\".py"
    : >"$REPO13/back\\-slash.py"
    : >"$REPO13/plain space.py"
    # A non-ASCII name is the case the v1 parse could not decode: the é arrives octal-escaped as
    # \303\251, which a quote-strip alone leaves naming no file. The ASCII fixtures above
    # all pass either parse, so without this one the parity check stays green while the two
    # parsers diverge on exactly the path detect.sh was moved to -z to reach.
    : >"$REPO13/café.py"
    cp "$ALL_SHAPES" "$REPO13/renamed-src.py"
    git -C "$REPO13" add renamed-src.py
    git -C "$REPO13" -c user.email=t@example.com -c user.name=t commit -qm init
    mv "$REPO13/renamed-src.py" "$REPO13/renamed-dst.py"
    git -C "$REPO13" add -N renamed-dst.py

    # Extract the porcelain invocation too, not just the awk program. Hardcoding either form here
    # would let the harness mask a mismatch: feeding -z to a v1 program makes the v1 program look
    # correct, because -z output carries no quoting for it to fail at decoding. Reading both ends
    # from SKILL.md means the fixtures below test the line as it actually runs.
    skill_porcelain="$(sed -n 's/^Uncommitted code files: !`\(git status --porcelain[^|]*\)|.*/\1/p' "$SKILL_MD")"
    if [[ -z "$skill_porcelain" ]]; then
      fail "SKILL.md porcelain invocation extracted" "non-empty command" "no match — line shape changed"
    else
      pass "SKILL.md porcelain invocation extracted"
    fi
    skill_out="$(cd "$REPO13" && eval "$skill_porcelain" | awk "$skill_awk")"

    assert_contains "SKILL.md parser reads a non-ASCII path undecoded" "$skill_out" 'café.py'
    assert_not_contains "SKILL.md parser leaks no octal escape" "$skill_out" '\303'
    assert_contains "SKILL.md parser unescapes an embedded quote" "$skill_out" 'quote".py'
    assert_contains "SKILL.md parser unescapes an embedded backslash" "$skill_out" 'back\-slash.py'
    assert_contains "SKILL.md parser unwraps a spaced path" "$skill_out" 'plain space.py'
    assert_contains "SKILL.md parser takes the worktree-rename new path" "$skill_out" 'renamed-dst.py'
    assert_not_contains "SKILL.md parser leaves no rename arrow" "$skill_out" ' -> '
    assert_not_contains "SKILL.md parser leaves no escaped quote" "$skill_out" '\"'

    # Parity with detect.sh over the same tree: every code file detect.sh audits must also
    # appear in the preview, or the model is shown a tree the audit does not agree with.
    detect_out="$(cd "$REPO13" && bash "$DETECT")"
    parity_ok=1
    while IFS= read -r audited; do
      [[ -z "$audited" ]] && continue
      case "$skill_out" in
      *"$audited"*) ;;
      *)
        parity_ok=0
        printf '  detect.sh audited but preview missed: %s\n' "$audited" >&2
        ;;
      esac
    done < <(printf '%s\n' "$detect_out" | sed -n 's/^Summary file: \(.*\) | T1=.*$/\1/p')
    if [[ "$parity_ok" -eq 1 ]]; then
      pass "SKILL.md preview covers every file detect.sh audits"
    else
      fail "SKILL.md preview covers every file detect.sh audits" "full coverage" "see above"
    fi
  fi
fi

# --- 11. Paths v1 porcelain escapes or renders ambiguously (#3126) ---------------------
# The v1 record cannot be parsed back reliably: git wraps and C-style-escapes any path holding a
# non-ASCII byte, a tab, or a backslash, and its "old -> new" rename rendering is byte-identical
# to an ordinary file literally named "left -> right.py". Reading -z instead removes the encoding
# entirely. Kept in its own repo so REPO13's parity fixture stays as 0.13.3 wrote it.
REPO14="$TEST_TMPDIR/repo14"
mkdir -p "$REPO14"
git -C "$REPO14" init -q
cp "$ALL_SHAPES" "$REPO14/left -> right.py"
cp "$ALL_SHAPES" "$REPO14/café.py"
cp "$ALL_SHAPES" "$REPO14/$(printf 'tab\there.py')"
escaped_out="$(cd "$REPO14" && bash "$DETECT")"
assert_contains "arrow-in-filename audited, not split as a rename" "$escaped_out" "left -> right.py"
assert_contains "non-ASCII path audited without escape mangling" "$escaped_out" "café.py"
assert_contains "tab-bearing path audited" "$escaped_out" "$(printf 'tab\there.py')"
assert_not_contains "escaped paths are not reported as files=0" "$escaped_out" "files=0"
assert_not_contains "no C-style octal escape leaks into a target path" "$escaped_out" '\303'

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
