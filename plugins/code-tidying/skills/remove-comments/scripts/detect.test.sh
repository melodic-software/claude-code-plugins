#!/usr/bin/env bash
# test-scope: plugins/code-tidying/skills/remove-comments/actions/audit.md plugins/code-tidying/scripts/generated-marker.ere
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
SKIPPED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
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

NAME_PROBE_REPO="$TEST_TMPDIR/nameprobe"
mkdir -p "$NAME_PROBE_REPO"
git -C "$NAME_PROBE_REPO" init -q
host_can_name() {
  local name="$1" rc=1
  if : >"$NAME_PROBE_REPO/$name" 2>/dev/null && [[ -f "$NAME_PROBE_REPO/$name" ]]; then
    if grep -qxF "?? $name" < <(git -C "$NAME_PROBE_REPO" status --porcelain -z 2>/dev/null |
      tr '\0' '\n'); then
      rc=0
    fi
  fi
  rm -f -- "$NAME_PROBE_REPO/$name" 2>/dev/null
  return "$rc"
}

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

STRINGS="$TEST_TMPDIR/strings.js"
cat >"$STRINGS" <<'EOF'
const url = "https://example.com/used to do X; now does Y";
const s = "text";  // used to return null
// it's no longer used
EOF

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

help_exit=0
bash "$DETECT" --help >/dev/null 2>&1 || help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"

unknown_exit=0
bash "$DETECT" --bogus >/dev/null 2>&1 || unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"

out="$(bash "$DETECT" "$ALL_SHAPES")"
assert_contains "history-narration finding" "$out" "Finding shape: history-narration"
assert_contains "conversational-antecedent finding" "$out" "Finding shape: conversational-antecedent"
assert_contains "plan-reference finding" "$out" "Finding shape: plan-reference"
assert_contains "ticket-pr-residue finding" "$out" "Finding shape: ticket-pr-residue"
assert_contains "ticket-pr-residue is tier 2" "$out" "Finding tier: 2"
assert_contains "file summary present" "$out" "Summary file: $ALL_SHAPES"

clean_out="$(bash "$DETECT" "$CLEAN")"
assert_contains "clean summary present" "$clean_out" "Summary total:"
assert_not_contains "code identifier 'previously' (no comment) not flagged" "$clean_out" "Finding shape: history-narration"
assert_not_contains "UTF-8 / SHA-256 not a ticket ref" "$clean_out" "Finding shape: ticket-pr-residue"
assert_not_contains "sanctioned TODO(#123) not flagged" "$clean_out" "Finding line: 5"


strings_out="$(bash "$DETECT" "$STRINGS")"
assert_not_contains "residue words inside a quoted URL are not flagged" "$strings_out" "Finding line: 1"
assert_contains "real comment after a closed string is still flagged" "$strings_out" "Finding line: 2"
assert_contains "apostrophe in comment prose does not suppress residue" "$strings_out" "Finding line: 3"


ticket_out="$(bash "$DETECT" "$TICKET")"
assert_contains "bare JIRA-123 key detected" "$ticket_out" "Finding shape: ticket-pr-residue"


opt_out="$(bash "$DETECT" "$OPTOUT")"
assert_contains "control residue still detected" "$opt_out" "Finding shape: plan-reference"
assert_not_contains "opt-out history suppressed" "$opt_out" "used to do x"
assert_not_contains "opt-out inline-line suppressed" "$opt_out" "Finding shape: conversational-antecedent"

MD_FIXTURE="$TEST_TMPDIR/notes.md"
cat >"$MD_FIXTURE" <<'EOF'
used to do X, now does Y — per your request.
EOF
md_out="$(bash "$DETECT" "$MD_FIXTURE")"
assert_contains "markdown target yields no code files" "$md_out" "files=0"

DIR_FIXTURE="$TEST_TMPDIR/dir-target/nested"
mkdir -p "$DIR_FIXTURE"
cp "$ALL_SHAPES" "$DIR_FIXTURE/inner.py"
dir_out="$(bash "$DETECT" "$TEST_TMPDIR/dir-target")"
assert_contains "directory target audits nested code file" "$dir_out" "Summary file: $DIR_FIXTURE/inner.py"
assert_contains "directory target finds shapes" "$dir_out" "Finding shape: history-narration"

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$CLEAN" >"$PATHS"
pf_out="$(bash "$DETECT" --paths-file "$PATHS")"
assert_contains "paths-file target audited" "$pf_out" "Summary file: $CLEAN"

missing_val_exit=0
timeout 10 bash "$DETECT" --paths-file >/dev/null 2>&1 || missing_val_exit=$?
assert_exit "--paths-file with missing value exits 2" 2 "$missing_val_exit"

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


REPO9="$TEST_TMPDIR/repo9"
mkdir -p "$REPO9"
git -C "$REPO9" init -q
cp "$ALL_SHAPES" "$REPO9/my helper.py"

spaced_out="$(cd "$REPO9" && bash "$DETECT")"
assert_not_contains "spaced default target is not reported as files=0" "$spaced_out" "files=0"
assert_not_contains "spaced default target does not claim a clean tree" "$spaced_out" "no code targets"
assert_contains "spaced default target audited" "$spaced_out" "Summary file: my helper.py"
assert_contains "spaced default target finds shapes" "$spaced_out" "Finding shape: history-narration"

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


SKILL_MD="$SCRIPT_DIR/../actions/audit.md"
PREVIEW_SCRIPT="$SCRIPT_DIR/../../../scripts/changed-code-files.sh"
if [[ ! -f "$SKILL_MD" || ! -f "$PREVIEW_SCRIPT" ]]; then
  fail "preview surfaces located for parity check" "actions/audit.md and scripts/changed-code-files.sh" "missing"
else
  if ! grep -qF '<skill-dir>/scripts/changed-code-files.sh' "$SKILL_MD"; then
    fail "audit action lists files with the shared script" "a call through <skill-dir>/scripts/changed-code-files.sh" "line shape changed"
  else
    pass "audit action lists files with the shared script"

    REPO13="$TEST_TMPDIR/repo13"
    mkdir -p "$REPO13"
    git -C "$REPO13" init -q
    if host_can_name 'quote".py'; then : >"$REPO13/quote\".py"; fi
    if host_can_name 'back\-slash.py'; then : >"$REPO13/back\\-slash.py"; fi
    : >"$REPO13/plain space.py"
    : >"$REPO13/café.py"
    cp "$ALL_SHAPES" "$REPO13/renamed-src.py"
    git -C "$REPO13" add renamed-src.py
    git -C "$REPO13" -c user.email=t@example.com -c user.name=t commit -qm init
    mv "$REPO13/renamed-src.py" "$REPO13/renamed-dst.py"
    git -C "$REPO13" add -N renamed-dst.py

    skill_out="$(cd "$REPO13" && bash "$PREVIEW_SCRIPT")"

    assert_contains "preview script reads a non-ASCII path undecoded" "$skill_out" 'café.py'
    assert_not_contains "preview script leaks no octal escape" "$skill_out" '\303'
    if host_can_name 'quote".py'; then
      assert_contains "preview script unescapes an embedded quote" "$skill_out" 'quote".py'
    else
      skip "preview script unescapes an embedded quote" \
        'a double quote does not survive into a filename git can see here'
    fi
    if host_can_name 'back\-slash.py'; then
      assert_contains "preview script unescapes an embedded backslash" "$skill_out" 'back\-slash.py'
    else
      skip "preview script unescapes an embedded backslash" \
        'a backslash does not survive into a filename git can see here'
    fi
    assert_contains "preview script unwraps a spaced path" "$skill_out" 'plain space.py'
    assert_contains "preview script takes the worktree-rename new path" "$skill_out" 'renamed-dst.py'
    assert_not_contains "preview script leaves no rename arrow" "$skill_out" ' -> '
    assert_not_contains "preview script leaves no escaped quote" "$skill_out" '\"'

    detect_out="$(cd "$REPO13" && bash "$DETECT")"
    mapfile -t audited_paths < <(printf '%s\n' "$detect_out" | sed -n 's/^Summary file: \(.*\) | T1=.*$/\1/p')
    parity_ok=1
    for audited in ${audited_paths[@]+"${audited_paths[@]}"}; do
      [[ -z "$audited" ]] && continue
      case "$skill_out" in
      *"$audited"*) ;;
      *)
        parity_ok=0
        printf '  detect.sh audited but preview missed: %s\n' "$audited" >&2
        ;;
      esac
    done
    if [[ "$parity_ok" -eq 1 ]]; then
      pass "SKILL.md preview covers every file detect.sh audits"
    else
      fail "SKILL.md preview covers every file detect.sh audits" "full coverage" "see above"
    fi

    reverse_ok=1
    while IFS= read -r previewed; do
      [[ -z "$previewed" ]] && continue
      matched=0
      for audited in ${audited_paths[@]+"${audited_paths[@]}"}; do
        if [[ "$previewed" == "$audited" ]]; then
          matched=1
          break
        fi
      done
      if [[ "$matched" -eq 0 ]]; then
        reverse_ok=0
        printf '  preview emitted a path detect.sh did not audit: %s\n' "$previewed" >&2
      fi
    done < <(printf '%s\n' "$skill_out")
    if [[ "$reverse_ok" -eq 1 ]]; then
      pass "SKILL.md preview emits no path detect.sh did not audit"
    else
      fail "SKILL.md preview emits no path detect.sh did not audit" "no extra paths" "see above"
    fi
  fi
fi

REPO14="$TEST_TMPDIR/repo14"
mkdir -p "$REPO14"
git -C "$REPO14" init -q
TAB_NAME="$(printf 'tab\there.py')"
if host_can_name 'left -> right.py'; then cp "$ALL_SHAPES" "$REPO14/left -> right.py"; fi
cp "$ALL_SHAPES" "$REPO14/café.py"
if host_can_name "$TAB_NAME"; then
  cp "$ALL_SHAPES" "$REPO14/$TAB_NAME"
fi
escaped_out="$(cd "$REPO14" && bash "$DETECT")"
if host_can_name 'left -> right.py'; then
  assert_contains "arrow-in-filename audited, not split as a rename" "$escaped_out" "left -> right.py"
else
  skip "arrow-in-filename audited, not split as a rename" \
    'a > does not survive into a filename git can see here'
fi
assert_contains "non-ASCII path audited without escape mangling" "$escaped_out" "café.py"
if host_can_name "$TAB_NAME"; then
  assert_contains "tab-bearing path audited" "$escaped_out" "$TAB_NAME"
else
  skip "tab-bearing path audited" 'a tab does not survive into a filename git can see here'
fi
assert_not_contains "escaped paths are not reported as files=0" "$escaped_out" "files=0"
assert_not_contains "no C-style octal escape leaks into a target path" "$escaped_out" '\303'

ORIGIN="$SCRIPT_DIR/../evals/fixtures/origin-notes.sh"
origin_out="$(bash "$DETECT" "$ORIGIN")"
assert_contains "origin-note shape emitted" "$origin_out" "Finding shape: origin-note"
assert_contains "origin-note is tier 1" "$origin_out" $'Finding tier: 1\nFinding shape: origin-note'
assert_contains "five origin notes and no other finding" "$origin_out" "T1=5 T2=0 T3=0"
assert_contains "ported-from flagged" "$origin_out" "(ported from the melodic-software dotfiles profile)"
assert_contains "merged-date flagged" "$origin_out" "Merged 2026-07-24 from dot_bashrc"
assert_contains "added-date flagged" "$origin_out" "Added 2026-08-10 while wiring"
assert_contains "copied-from flagged" "$origin_out" "Copied from the provisioning repo"
assert_contains "backported-date flagged" "$origin_out" "Backported 2026-09-01 from main"
assert_not_contains "copyright header is not an origin note" "$origin_out" "Copyright (c) 2026"
assert_not_contains "SPDX header is not an origin note" "$origin_out" "SPDX-License-Identifier"
assert_not_contains "license-grant header is not an origin note" "$origin_out" "Licensed under the MIT License"
assert_not_contains "freshness stamp is not an origin note" "$origin_out" "verified 2026-09-03"
assert_not_contains "no stamp verb reads as an origin note" "$origin_out" "2026-09-03"
assert_not_contains "why-comment is not an origin note" "$origin_out" "Must stay ordered"
assert_not_contains "bare date is not an origin note" "$origin_out" "Finding excerpt: # 2026-08-10"
assert_not_contains "sanctioned TODO is not an origin note" "$origin_out" "TODO(#123)"

ORIGIN_OPTOUT="$TEST_TMPDIR/origin-optout.py"
cat >"$ORIGIN_OPTOUT" <<'EOF'
# Merged 2026-07-24 from dot_bashrc
# comment-residue-ignore
# ported from the dotfiles profile
value = 1  # Copied from upstream  # comment-residue-ignore
EOF
origin_optout_out="$(bash "$DETECT" "$ORIGIN_OPTOUT")"
assert_contains "origin-note control still detected" "$origin_optout_out" "Finding shape: origin-note"
assert_not_contains "origin-note marker opt-out (previous line)" "$origin_optout_out" "ported from the dotfiles"
assert_not_contains "origin-note marker opt-out (same line)" "$origin_optout_out" "Copied from upstream"

ORIGIN_NEG="$TEST_TMPDIR/origin-negatives.py"
cat >"$ORIGIN_NEG" <<'EOF'
# helpers exported from index.ts
# values imported from utils
# supported from version 3.0 onward
# padded 2026-01-01 for alignment
# bytes copied from the source buffer are hashed
# rows migrated from a legacy schema each tick
# cache helper\ copied from the dotfiles profile
EOF
origin_neg_out="$(bash "$DETECT" "$ORIGIN_NEG")"
assert_contains "origin-note word and clause boundaries hold" "$origin_neg_out" "T1=0 T2=0 T3=0"

ORIGIN_EXEMPT="$TEST_TMPDIR/origin-exempt.py"
cat >"$ORIGIN_EXEMPT" <<'EOF'
# TODO(#123): ported from lib/x
# TODO: ported from lib/x
# FIXME: copied from the vendor SDK

# Copyright 2019 Acme Corp. Adapted from lib/x

# (c) 2019 Acme Corp. Copied from lib/x

# SPDX-License-Identifier: MIT; copied from the upstream license text

# Licensed under the MIT License; ported from the vendor SDK

# License: Apache-2.0, adapted from the reference implementation

# Ported from lib/x
EOF
origin_exempt_out="$(bash "$DETECT" "$ORIGIN_EXEMPT")"
assert_contains "an ordinary origin note still fires beside the exempt lines" "$origin_exempt_out" "Finding excerpt: # Ported from lib/x"
assert_contains "marker and license comments are exempt from origin-note" "$origin_exempt_out" "T1=1 T2=0 T3=0"

ORIGIN_BLOCK="$TEST_TMPDIR/origin-block.js"
cat >"$ORIGIN_BLOCK" <<'EOF'
/*
 * Copyright (c) 2019 Acme Corp.
 * Ported from the reference implementation.
 * Licensed under the MIT License.
 */

// BLK1: Ported from the reference implementation.
const a = 1;
// BLK2: Copied from the reference implementation.
EOF
origin_block_out="$(bash "$DETECT" "$ORIGIN_BLOCK")"
assert_not_contains "a cue-less line inside a NOTICE block is exempt" "$origin_block_out" "Finding excerpt: * Ported from the reference implementation."
assert_contains "the same sentence after a blank line still fires" "$origin_block_out" "Finding excerpt: // BLK1: Ported from the reference implementation."
assert_contains "the same sentence after a code line still fires" "$origin_block_out" "Finding excerpt: // BLK2: Copied from the reference implementation."
assert_contains "only the NOTICE block is exempt" "$origin_block_out" "T1=2 T2=0 T3=0"

ORIGIN_BLOCK_HASH="$TEST_TMPDIR/origin-block-hash.sh"
cat >"$ORIGIN_BLOCK_HASH" <<'EOF'
# Copyright 2019 Acme Corp.
# Ported from the reference implementation.
value=1
# HASH1: Ported from the reference implementation.
EOF
origin_block_hash_out="$(bash "$DETECT" "$ORIGIN_BLOCK_HASH")"
assert_not_contains "a hash NOTICE run is exempt whole" "$origin_block_hash_out" "Finding excerpt: # Ported from the reference implementation."
assert_contains "a hash run after code still fires" "$origin_block_hash_out" "Finding excerpt: # HASH1: Ported from the reference implementation."
assert_contains "only the hash NOTICE run is exempt" "$origin_block_hash_out" "T1=1 T2=0 T3=0"

ORIGIN_LEADER="$TEST_TMPDIR/origin-leader.cs"
cat >"$ORIGIN_LEADER" <<'EOF'
/// Ported from the reference implementation.
//! Ported from the reference implementation.
EOF
origin_leader_out="$(bash "$DETECT" "$ORIGIN_LEADER")"
assert_contains "a /// doc-comment leader does not block the anchor" "$origin_leader_out" "Finding excerpt: /// Ported from the reference implementation."
assert_contains "a //! doc-comment leader does not block the anchor" "$origin_leader_out" "Finding excerpt: //! Ported from the reference implementation."
assert_contains "both doc-comment forms are findings" "$origin_leader_out" "T1=2 T2=0 T3=0"

ORIGIN_TERM="$TEST_TMPDIR/origin-terminator.js"
cat >"$ORIGIN_TERM" <<'EOF'
// ported fromage is a cheese
// Copied fromage shop inventory
// Added 2026-09-011 to the list
// Added 2026-09-01x to the list
EOF
origin_term_out="$(bash "$DETECT" "$ORIGIN_TERM")"
assert_contains "the cue must end on a boundary" "$origin_term_out" "T1=0 T2=0 T3=0"

ORIGIN_DT="$TEST_TMPDIR/origin-datetime.js"
cat >"$ORIGIN_DT" <<'EOF'
// Added 2026-09-01T12:00 from the vendor feed
// Merged 2026-09-01T12:00:00Z from the vendor feed
// Added 2026-09-01T12:00:00+01:00 from the vendor feed
EOF
origin_dt_out="$(bash "$DETECT" "$ORIGIN_DT")"
assert_contains "an ISO-8601 datetime is still an origin note" "$origin_dt_out" "T1=3 T2=0 T3=0"

ORIGIN_NARROW="$TEST_TMPDIR/origin-narrow.js"
cat >"$ORIGIN_NARROW" <<'EOF'
// NAR1: Ported from the legacy fork to satisfy the copyright audit.

// NAR2: Copied from the legacy fork; the callback signature f(c) is unchanged.
EOF
origin_narrow_out="$(bash "$DETECT" "$ORIGIN_NARROW")"
assert_contains "a bare copyright mention does not exempt" "$origin_narrow_out" "Finding excerpt: // NAR1: Ported from the legacy fork"
assert_contains "a yearless (c) token does not exempt" "$origin_narrow_out" "Finding excerpt: // NAR2: Copied from the legacy fork"
assert_contains "both narrowed cases are findings again" "$origin_narrow_out" "T1=2 T2=0 T3=0"

ORIGIN_BOTH="$TEST_TMPDIR/origin-both.py"
cat >"$ORIGIN_BOTH" <<'EOF'
# Merged 2026-07-24 from branch feature/x
EOF
origin_both_out="$(bash "$DETECT" "$ORIGIN_BOTH")"
assert_contains "origin-note reports the branch-bearing line" "$origin_both_out" "Finding shape: origin-note"
assert_contains "ticket-pr-residue reports the same line" "$origin_both_out" "Finding shape: ticket-pr-residue"
assert_contains "double-fire is one T1 and one T2" "$origin_both_out" "T1=1 T2=1 T3=0"


PROSE_NEG="$TEST_TMPDIR/prose-neg.yml"
cat >"$PROSE_NEG" <<'EOF'
# runs on every pull request before merge
steps:
  - run: true  # in this committed configuration we pin the toolchain
EOF
prose_neg_out="$(bash "$DETECT" "$PROSE_NEG")"
assert_not_contains "plain pull request prose is not ticket-pr-residue" "$prose_neg_out" "Finding shape: ticket-pr-residue"
assert_not_contains "in this committed is not plan-reference" "$prose_neg_out" "Finding shape: plan-reference"

FEATURE_BRANCH="$TEST_TMPDIR/feature-branch.js"
cat >"$FEATURE_BRANCH" <<'EOF'
// from the feature branch
EOF
feature_branch_out="$(bash "$DETECT" "$FEATURE_BRANCH")"
assert_contains "from the feature branch is ticket-pr-residue" "$feature_branch_out" "Finding shape: ticket-pr-residue"


CUE_N=0
cue_file() {
  CUE_N=$((CUE_N + 1))
  local f="$TEST_TMPDIR/cue-$CUE_N.py"
  printf '# %s\n' "$1" >"$f"
  printf '%s' "$f"
}
expect_shape() {
  local out
  out="$(bash "$DETECT" "$(cue_file "$2")")"
  assert_contains "$1" "$out" "Finding shape: $3"
}
expect_clean() {
  local out
  out="$(bash "$DETECT" "$(cue_file "$2")")"
  assert_contains "$1" "$out" "T1=0 T2=0 T3=0"
}

expect_shape "example: used to" "used to buffer writes" history-narration
expect_shape "example: no longer" "no longer needed after the rewrite" history-narration
expect_shape "example: previously" "previously a linked list" history-narration
expect_shape "example: renamed from" "renamed from fetchAll" history-narration
expect_shape "example: we switched from" "we switched from polling to events" history-narration
expect_shape "example: now returns" "now returns a copy" history-narration
expect_shape "example: Task 2 replaces the old" "Task 2 replaces the old tokenizer" plan-reference
expect_shape "example: as planned" "as planned" plan-reference
expect_shape "example: in this PR" "in this PR" plan-reference
expect_shape "example: in this commit" "in this commit" plan-reference
expect_shape "example: in this refactor" "in this refactor" plan-reference
expect_shape "example: per your request" "per your request" conversational-antecedent
expect_shape "example: as you asked" "as you asked" conversational-antecedent
expect_shape "example: like you said" "like you said" conversational-antecedent
expect_shape "example: per our discussion" "per our discussion" conversational-antecedent
expect_shape "example: see PR #45" "see PR #45" ticket-pr-residue
expect_shape "example: bare repo#N" "dotfiles#647" ticket-pr-residue
expect_shape "example: repo#N inside prose" "fixed upstream, see dotfiles#647 for details" ticket-pr-residue
expect_shape "example: org/repo#N" "melodic-software/dotfiles#647" ticket-pr-residue
expect_shape "example: from the feature branch" "from the feature branch" ticket-pr-residue
expect_shape "example: JIRA-123" "JIRA-123" ticket-pr-residue

expect_clean "used tokens is not used to" "used tokens are cached"
expect_clean "reformerly is not formerly" "reformerly"
expect_clean "previouslyx is not previously" "previouslyx"
expect_clean "no longerx is not no longer" "no longerx"
expect_clean "unchanged to is not changed to" "unchanged to the caller"
expect_clean "changed tomorrow is not changed to" "changed tomorrow"
expect_clean "prerenamed from is not renamed from" "prerenamed from x"
expect_clean "unrefactored into is not refactored into" "unrefactored into modules"
expect_clean "we switchedly is not we switched" "we switchedly"
expect_clean "this used tokens is not this used to" "this used tokens"
expect_clean "now doesnt is not now does" "now doesnt"
expect_clean "now returnsx is not now returns" "now returnsx"
expect_clean "per the planet is not per the plan" "per the planet"
expect_clean "as plannedly is not as planned" "as plannedly"
expect_clean "replaces the older is not replaces the old" "replaces the older"
expect_clean "in this prior is not in this pr" "in this prior"
expect_clean "in this committed is not in this commit" "in this committed"
expect_clean "in this sessions is not in this session" "in this sessions"
expect_clean "step 2 in the planet is not the plan cue" "step 2 in the planet"
expect_clean "per your requestor is not per your request" "per your requestor"
expect_clean "as requestedly is not as requested" "as requestedly"
expect_clean "per our chatter is not per our chat" "per our chatter"
expect_clean "as you askedn is not as you asked" "as you askedn"
expect_clean "as we decidedly is not as we decided" "as we decidedly"
expect_clean "you wantedly is not you wanted" "you wantedly"
expect_clean "like you saidx is not like you said" "like you saidx"
expect_clean "pull request in plain prose" "runs on every pull request before merge"

expect_shape "cue followed by punctuation" "used to, until the rewrite" history-narration

expect_clean "C#7 is not a reference" "C#7 records need the newer compiler"
expect_clean "F# 3 is not a reference" "F# 3 supports type providers"
expect_clean "A#5 is not a reference" "A#5 is a note name"
expect_clean "see section #3 is not a reference" "see section #3"
expect_clean "bare (#3126) is not counted" "fixes the loop (#3126)"

expect_clean "TODO(#n) exempts its ticket ref" "TODO(#123): see PR #45"
expect_clean "TODO: exempts its ticket ref" "TODO: see PR #45"
expect_clean "clause-opening FIXME: exempts" "note; FIXME: from branch x"
expect_shape "marker mentioned mid-sentence exempts nothing" "see PR #45 and the TODO list" ticket-pr-residue
expect_shape "bare TODO without ( or : exempts nothing" "TODO fix, see PR #45" ticket-pr-residue
expect_shape "marker inside a longer word exempts nothing" "TODOS: see PR #45" ticket-pr-residue

expect_no_shape() {
  local out
  out="$(bash "$DETECT" "$(cue_file "$2")")"
  assert_not_contains "$1" "$out" "Finding shape: $3"
}
weak_out="$(bash "$DETECT" "$(cue_file "exactly as before")")"
assert_contains "weak cue reports tier 2" "$weak_out" "Finding tier: 2"
assert_contains "weak cue T2 summary" "$weak_out" "T1=0 T2=1 T3=0"
expect_shape "weak: exactly as before" "exactly as before" history-narration-weak
expect_shape "weak: as before" "keeps the order as before" history-narration-weak
expect_shape "weak: has always used" "this has always used a lock" history-narration-weak
expect_shape "weak: always used" "always used a lock here" history-narration-weak
expect_shape "weak: the old shared group" "the old shared group" history-narration-weak
expect_shape "weak: (ci-perf Phase 6b)" "(ci-perf Phase 6b)" history-narration-weak
expect_shape "weak: bare phase number before punctuation" "runs in phase 3, then stops" history-narration-weak
expect_shape "weak: bare phase number ends the comment" "cleanup for Phase 6" history-narration-weak
expect_shape "weak: as before before the loop stays a finding" "as before the loop starts" history-narration-weak
expect_shape "weak: cue after punctuation" "fine;as before" history-narration-weak

expect_clean "as beforehand is not as before" "as beforehand"
expect_clean "alias before is not as before" "alias before the loop"
expect_clean "always usedx is not always used" "always usedx"
expect_clean "the older is not the old" "the older shared group"
expect_clean "the oldest is not the old" "the oldest entry wins"
expect_clean "the old-style is not the old word" "the old-style form"
expect_clean "trailing the old is not the old word" "the old"
expect_clean "phase 2 of the build is prose" "phase 2 of the build"
expect_clean "the second phase is prose" "the second phase"
expect_clean "in phase two is prose" "in phase two"
expect_clean "biphase 2b is not a phase cue" "biphase 2b"
expect_clean "phase 6bx is not a phase cue" "phase 6bx"
expect_clean "phase 2 samples is prose" "phase 2 samples the signal"
expect_no_shape "replaces the old is plan-reference, not weak" "Task 2 replaces the old tokenizer" history-narration-weak
expect_shape "replaces the old stays plan-reference" "Task 2 replaces the old tokenizer" plan-reference
expect_shape "the old after replaces the old still counts" "replaces the old tokenizer; the old shared group" history-narration-weak
expect_no_shape "identifier is not a comment" 'the_old_shared = 1' history-narration-weak

wrap_fixture() {
  local f="$TEST_TMPDIR/wrap-$1.py"
  cat >"$f"
  printf '%s' "$f"
}
wrap_count() { grep -c '^Finding shape:' <<<"$1" || true; }
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

wrap_out="$(bash "$DETECT" "$(wrap_fixture basic <<'EOF'
x = 1
# grouped for speed (ci-perf Phase
# 6b) and nothing else
y = 2
EOF
)")"
assert_contains "wrapped Phase 6b is found" "$wrap_out" "Finding shape: history-narration-weak"
assert_contains "wrapped finding sits on the first line" "$wrap_out" "Finding line: 2"
assert_not_contains "wrapped finding is not repeated on the second line" "$wrap_out" "Finding line: 3"
assert_contains "wrapped excerpt shows both halves" "$wrap_out" "Finding excerpt: grouped for speed (ci-perf Phase 6b) and nothing else"
assert_contains "wrapped finding is counted once" "$wrap_out" "T1=0 T2=1 T3=0"

wrap_out="$(bash "$DETECT" "$(wrap_fixture tier1 <<'EOF'
# tuned as you
# asked last week
EOF
)")"
assert_contains "wrapped tier-1 cue is found" "$wrap_out" "Finding shape: conversational-antecedent"
assert_contains "wrapped tier-1 cue sits on the first line" "$wrap_out" "Finding line: 1"

wrap_out="$(bash "$DETECT" "$(wrap_fixture slashes <<'EOF'
// used
// to be a list
EOF
)")"
assert_contains "wrapped cue over // comments" "$wrap_out" "Finding shape: history-narration"

wrap_out="$(bash "$DETECT" "$(wrap_fixture block <<'EOF'
/*
 * the old
 * shared group is gone
 */
EOF
)")"
assert_contains "wrapped cue over block-comment lines" "$wrap_out" "Finding shape: history-narration-weak"
assert_contains "block-comment finding sits on the first line" "$wrap_out" "Finding line: 2"

wrap_out="$(bash "$DETECT" "$(wrap_fixture once <<'EOF'
# keeps the order as before
# for every caller
EOF
)")"
assert_eq "a single-line finding is not reported again when joined" "1" "$(wrap_count "$wrap_out")"

wrap_out="$(bash "$DETECT" "$(wrap_fixture both <<'EOF'
# as before, see PR #45
# and the old shared group
EOF
)")"
assert_eq "two lines with own findings give three findings" "3" "$(wrap_count "$wrap_out")"
first_line="$(grep -m1 '^Finding line:' <<<"$wrap_out")"
assert_eq "own findings keep line order" "Finding line: 1" "$first_line"

wrap_out="$(bash "$DETECT" "$(wrap_fixture nojoin <<'EOF'
# grouped (ci-perf Phase
value = 6
# 6b) ends here
#
# (ci-perf Phase
#
# 6b) ends here
EOF
)")"
assert_contains "no join across code or a blank comment line" "$wrap_out" "T1=0 T2=0 T3=0"

wrap_out="$(bash "$DETECT" "$(wrap_fixture trailing <<'EOF'
# grouped (ci-perf Phase
value = 6  # 6b) ends here
EOF
)")"
assert_contains "code line with a trailing comment starts no join" "$wrap_out" "T1=0 T2=0 T3=0"

wrap_out="$(bash "$DETECT" "$(wrap_fixture ignore <<'EOF'
# grouped (ci-perf Phase
# 6b) ends here comment-residue-ignore
# ok (ci-perf Phase comment-residue-ignore
# 6b) ends here
# comment-residue-ignore
# (ci-perf Phase
# 6b) ends here
EOF
)")"
assert_contains "opt-out marker suppresses a joined finding" "$wrap_out" "T1=0 T2=0 T3=0"

wrap_out="$(bash "$DETECT" "$(wrap_fixture license <<'EOF'
# SPDX-License-Identifier: MIT
# vendored: ported
# from upstream
EOF
)")"
assert_contains "wrapped origin cue inside a license block is exempt" "$wrap_out" "T1=0 T2=0 T3=0"
wrap_out="$(bash "$DETECT" "$(wrap_fixture originwrap <<'EOF'
# vendored: ported
# from upstream
EOF
)")"
assert_contains "wrapped origin cue outside a license block is found" "$wrap_out" "Finding shape: origin-note"


REPOUP="$TEST_TMPDIR/repoup"
mkdir -p "$REPOUP/gen"
git -C "$REPOUP" init -q
printf '%s\n' '# SYNC-MANAGED FILE - DO NOT EDIT' '# used to buffer; now flushes' >"$REPOUP/synced.py"
printf '%s\n' '// @generated by codegen' '// used to buffer; now flushes' >"$REPOUP/gen/out.js"
printf '%s\n' '# used to buffer; now flushes' >"$REPOUP/plain.py"
printf '%s\n' '# SYNC-MANAGED FILE - DO NOT EDIT' 'x = 1' >"$REPOUP/synced-clean.py"

up_out="$(cd "$REPOUP" && bash "$DETECT" synced.py plain.py gen/out.js synced-clean.py)"
assert_contains "sync-managed header gets the upstream note" "$up_out" "Note: upstream (sync-managed or generated file) $REPOUP/synced.py"
assert_contains "@generated header gets the upstream note" "$up_out" "Note: upstream (sync-managed or generated file) $REPOUP/gen/out.js"
assert_not_contains "normal file gets no upstream note" "$up_out" "Note: upstream (sync-managed or generated file) $REPOUP/plain.py"
assert_not_contains "header file without findings gets no upstream note" "$up_out" "Note: upstream (sync-managed or generated file) $REPOUP/synced-clean.py"
assert_contains "upstream note precedes its summary line" "$up_out" "Note: upstream (sync-managed or generated file) $REPOUP/synced.py"$'\n'"Summary file: $REPOUP/synced.py | T1=1"
assert_contains "labeled finding still counts" "$up_out" "Summary total: files=4 T1=3 T2=0 T3=0"

printf '%s\n' '// Code generated by protoc-gen-go. DO NOT EDIT.' '// used to buffer; now flushes' >"$REPOUP/gen/pb.go"
printf '%s\n' '# GENERATED from lib/x.sh by scripts/sync-shared-copies.sh. Do not edit this copy:' '# used to buffer; now flushes' >"$REPOUP/copy.sh"
printf '%s\n' '# do not edit the order below' '# used to buffer; now flushes' >"$REPOUP/order.py"
marker_out="$(cd "$REPOUP" && bash "$DETECT" gen/pb.go copy.sh order.py)"
assert_contains "Go 'Code generated ... DO NOT EDIT.' header gets the upstream note" "$marker_out" "Note: upstream (sync-managed or generated file) $REPOUP/gen/pb.go"
assert_contains "'GENERATED from ... Do not edit this copy:' header gets the upstream note" "$marker_out" "Note: upstream (sync-managed or generated file) $REPOUP/copy.sh"
assert_not_contains "a hand-written 'do not edit the order below' gets no upstream note" "$marker_out" "Note: upstream (sync-managed or generated file) $REPOUP/order.py"
assert_contains "the hand-written file's finding still counts" "$marker_out" "Summary file: $REPOUP/order.py | T1=1"

printf '%s\n' '# comment' '' 'synced.py' 'gen/*' >"$REPOUP/excludes.txt"
ex_out="$(cd "$REPOUP" && bash "$DETECT" --exclude-from excludes.txt synced.py plain.py gen/out.js)"
assert_contains "--exclude-from reports the excluded count" "$ex_out" "Note: excluded 2 file(s) by --exclude-from"
assert_not_contains "--exclude-from skips a matching file" "$ex_out" "Summary file: $REPOUP/synced.py"
assert_not_contains "--exclude-from skips a matching glob" "$ex_out" "Summary file: $REPOUP/gen/out.js"
assert_contains "--exclude-from keeps a non-matching file" "$ex_out" "Summary file: $REPOUP/plain.py"
assert_contains "--exclude-from leaves the summary counting the rest" "$ex_out" "Summary total: files=1 T1=1 T2=0 T3=0"

ex_missing_exit=0
(cd "$REPOUP" && bash "$DETECT" --exclude-from nope.txt plain.py >/dev/null 2>&1) || ex_missing_exit=$?
assert_exit "--exclude-from with a missing file exits 2" 2 "$ex_missing_exit"
ex_noval_exit=0
timeout 10 bash "$DETECT" --exclude-from >/dev/null 2>&1 || ex_noval_exit=$?
assert_exit "--exclude-from with no value exits 2" 2 "$ex_noval_exit"


WORK="$TEST_TMPDIR/workaround.sh"
cat >"$WORK" <<'EOF'
# Workaround: the cache client drops the first write after a reconnect, so write twice.
cache_set "$k" "$v"  # work around the stale lock by writing again
# Workaround for the parser crash: https://example.org/bugs/88
# Workaround until the vendor SDK 4.2 ships: pin the v1 endpoint.
# Works around a renderer bug; remove when the renderer upgrade lands.
# Workaround: retry, and drop it once the driver fix ships.
# Workaround for upstream issue #412.
# Working around the encoder bug in owner/encoder#77.
workaround_count=0
echo "workaround in use"
# Workaround: the IDE holds a lock on the output folder;
# remove when the IDE releases it after a build.
x=1
# Workaround: retry until it succeeds.
x=1
# Workaround: pin the v4 client until v5.
x=1
# Workaround: keep the shim until upstream fixes the parser.
x=1
# Workaround: poll until fixed.
x=1
# Workaround: keep the shim until Node 22.
x=1
# Workaround: pin until Python 3.12 is the floor.
EOF
work_out="$(bash "$DETECT" "$WORK")"
wk_at() { printf 'Finding shape: unjustified-workaround\nFinding line: %s\n' "$1"; }
assert_contains "workaround with no link or removal condition is flagged" "$work_out" "$(wk_at 1)"
assert_contains "trailing workaround comment on a code line is flagged" "$work_out" "$(wk_at 2)"
assert_contains "unjustified-workaround is tier 2" "$work_out" $'Finding tier: 2\nFinding shape: unjustified-workaround'
assert_not_contains "a URL justifies the workaround" "$work_out" "$(wk_at 3)"
assert_not_contains "'until' justifies the workaround" "$work_out" "$(wk_at 4)"
assert_not_contains "'remove when' justifies the workaround" "$work_out" "$(wk_at 5)"
assert_not_contains "'once ... ships' justifies the workaround" "$work_out" "$(wk_at 6)"
assert_not_contains "an issue number justifies the workaround" "$work_out" "$(wk_at 7)"
assert_not_contains "an owner/repo#n reference justifies the workaround" "$work_out" "$(wk_at 8)"
assert_not_contains "the word in an identifier is not flagged" "$work_out" "$(wk_at 9)"
assert_not_contains "the word in a string literal is not flagged" "$work_out" "$(wk_at 10)"
assert_not_contains "a removal condition on the next comment line justifies the run" "$work_out" "$(wk_at 11)"
assert_not_contains "a workaround's justifying issue reference is not ticket residue" "$work_out" $'Finding shape: ticket-pr-residue\nFinding line: 7'
assert_not_contains "'until Node 22' justifies the workaround" "$work_out" "$(wk_at 22)"
assert_not_contains "'until Python 3.12' justifies the workaround" "$work_out" "$(wk_at 24)"
assert_contains "a bare 'until' loop bound does not justify the workaround" "$work_out" "$(wk_at 14)"
assert_not_contains "'until' a version justifies the workaround" "$work_out" "$(wk_at 16)"
assert_not_contains "'until upstream fixes' justifies the workaround" "$work_out" "$(wk_at 18)"
assert_not_contains "'until fixed' justifies the workaround" "$work_out" "$(wk_at 20)"
assert_contains "the file counts exactly the three unjustified workarounds" "$work_out" "Summary file: $WORK | T1=0 T2=3 T3=0"

TIDY_OLD="$TEST_TMPDIR/tidy-old.cs"
printf '%s\n' '// Workaround: the IDE locks analyzer DLLs; output to bin/cli/ when not building inside it' >"$TIDY_OLD"
assert_contains "tidy's old #14 example is flagged" "$(bash "$DETECT" "$TIDY_OLD")" "$(wk_at 1)"
TIDY_NEW="$TEST_TMPDIR/tidy-new.cs"
printf '%s\n' '// Workaround: the IDE locks analyzer DLLs; output to bin/cli/ when not building inside it, and remove when the IDE releases the lock after a build' >"$TIDY_NEW"
assert_contains "tidy's new #14 example is not flagged" "$(bash "$DETECT" "$TIDY_NEW")" "T1=0 T2=0 T3=0"


REPOADD="$TEST_TMPDIR/repoadd"
mkdir -p "$REPOADD"
git -C "$REPOADD" init -q
printf '%s\n' '# used to buffer writes' 'x = 1' >"$REPOADD/old.py"
printf '%s\n' '# used to buffer writes' >"$REPOADD/untouched.py"
git -C "$REPOADD" add -A
git -C "$REPOADD" -c user.email=t@example.com -c user.name=t commit -qm base
printf '%s\n' '# Workaround: write twice' 'y = 2' >>"$REPOADD/old.py"

add_out="$(cd "$REPOADD" && bash "$DETECT" --added-since HEAD)"
assert_contains "--added-since reports a finding on an added line" "$add_out" "$(wk_at 3)"
assert_not_contains "--added-since skips a finding on an unchanged line" "$add_out" "Finding line: 1"
assert_not_contains "--added-since leaves an unchanged file out" "$add_out" "untouched.py"
assert_contains "--added-since counts only the changed file" "$add_out" "Summary total: files=1 T1=0 T2=1 T3=0"

add_out="$(cd "$REPOADD" && bash "$DETECT" --added-since HEAD old.py untouched.py)"
assert_contains "--added-since with targets still filters to added lines" "$add_out" "Summary total: files=1 T1=0 T2=1 T3=0"

ln -s "$REPOADD" "$TEST_TMPDIR/repoadd-alias"
ALTGIT="$TEST_TMPDIR/altgit"
mkdir -p "$ALTGIT"
# shellcheck disable=SC2016 # the wrapper's source; $1, $2 and $@ expand when it runs
printf '#!/usr/bin/env bash\nif [[ "$1 $2" == "rev-parse --show-toplevel" ]]; then printf "%%s\\n" %q; exit 0; fi\nexec %q "$@"\n' \
  "$TEST_TMPDIR/repoadd-alias" "$(command -v git)" >"$ALTGIT/git"
chmod +x "$ALTGIT/git"
add_out="$(cd "$REPOADD" && PATH="$ALTGIT:$PATH" bash "$DETECT" --added-since HEAD old.py)"
assert_contains "--added-since keeps a target when git spells the root differently" "$add_out" "Summary total: files=1 T1=0 T2=1 T3=0"

add_rc=0
(cd "$REPOADD" && bash "$DETECT" --added-since no-such-ref >/dev/null 2>&1) || add_rc=$?
assert_exit "--added-since with an unknown base exits 2" 2 "$add_rc"
add_rc=0
timeout 10 bash "$DETECT" --added-since >/dev/null 2>&1 || add_rc=$?
assert_exit "--added-since with no value exits 2" 2 "$add_rc"

REPOWRAP="$TEST_TMPDIR/repowrap"
mkdir -p "$REPOWRAP"
git -C "$REPOWRAP" init -q
printf '%s\n' 'x = 1' '# grouped for speed (ci-perf Phase' 'y = 2' >"$REPOWRAP/second.py"
printf '%s\n' 'x = 1' '# 6b) and nothing else' 'y = 2' >"$REPOWRAP/first.py"
printf '%s\n' 'x = 1' '# comment-residue-ignore' 'y = 2' 'z = 3' >"$REPOWRAP/ignore.py"
git -C "$REPOWRAP" add -A
git -C "$REPOWRAP" -c user.email=t@example.com -c user.name=t commit -qm base
printf '%s\n' 'x = 1' '# grouped for speed (ci-perf Phase' '# 6b) and nothing else' 'y = 2' >"$REPOWRAP/second.py"
printf '%s\n' 'x = 1' '# grouped for speed (ci-perf Phase' '# 6b) and nothing else' 'y = 2' >"$REPOWRAP/first.py"
printf '%s\n' 'x = 1' '# comment-residue-ignore' '# used to buffer writes' 'y = 2' 'z = 3' '# used to buffer writes' >"$REPOWRAP/ignore.py"

wrap_add_out="$(cd "$REPOWRAP" && bash "$DETECT" --added-since HEAD)"
assert_contains "--added-since: wrapped pair with only its second line added is found at the first" \
  "$wrap_add_out" $'File: second.py\nFinding tier: 2\nFinding shape: history-narration-weak\nFinding line: 2\n'
assert_contains "--added-since: wrapped pair with only its first line added is found at the first" \
  "$wrap_add_out" $'File: first.py\nFinding tier: 2\nFinding shape: history-narration-weak\nFinding line: 2\n'
assert_contains "--added-since: a marker on an unchanged line suppresses the added line after it" \
  "$wrap_add_out" "Summary file: ignore.py | T1=1 T2=0 T3=0"
assert_contains "--added-since: the marker's control line is still found" \
  "$wrap_add_out" $'File: ignore.py\nFinding tier: 1\nFinding shape: history-narration\nFinding line: 6\n'

REPOCOST="$TEST_TMPDIR/repocost"
mkdir -p "$REPOCOST"
git -C "$REPOCOST" init -q
for ((i = 1; i <= 300; i++)); do printf '# counter %s\nx%s = %s\n' "$i" "$i" "$i"; done >"$REPOCOST/big.py"
git -C "$REPOCOST" add -A
git -C "$REPOCOST" -c user.email=t@example.com -c user.name=t commit -qm base
printf '%s\n' '# used to buffer writes' >>"$REPOCOST/big.py"
detect_calls() { grep -cE '^\++ cr_detect_shapes_text( |$)' "$1" || true; }

cost_out="$(cd "$REPOCOST" && PS4='+ ' bash -x "$DETECT" --added-since HEAD 2>"$TEST_TMPDIR/cost-added.trace")"
assert_contains "--added-since finds the one added line of a large file" "$cost_out" "Finding line: 601"
cost_added="$(detect_calls "$TEST_TMPDIR/cost-added.trace")"
(cd "$REPOCOST" && PS4='+ ' bash -x "$DETECT" big.py >/dev/null 2>"$TEST_TMPDIR/cost-whole.trace")
cost_whole="$(detect_calls "$TEST_TMPDIR/cost-whole.trace")"
if [[ "$cost_whole" =~ ^[0-9]+$ ]] && ((cost_whole >= 601)); then
  pass "the trace counts a detection call per line of a whole-file audit"
else
  fail "the trace counts a detection call per line of a whole-file audit" "at least 601" "$cost_whole"
fi
if [[ "$cost_added" =~ ^[0-9]+$ ]] && ((cost_added <= 10)); then
  pass "--added-since detection calls track the added lines, not the file length"
else
  fail "--added-since detection calls track the added lines, not the file length" "at most 10" "$cost_added"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed, %d host skip(s).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed, %d host skip(s).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
