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
SKIPPED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
# A case whose FIXTURE this filesystem cannot hold is neither a pass nor a
# failure of the detector. It prints its own visible line and carries its own
# counter, and never routes through pass(), so a proof this host could not run
# can never be read off the summary as one that did.
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

# Several cases name a file with a byte v1 porcelain escapes. Windows reserves `"`, `>` and
# a tab (MSYS substitutes them silently) and a backslash is a separator, so ask git itself
# whether the host can hold the name: `--porcelain -z` emits raw bytes with no C-quoting.
NAME_PROBE_REPO="$TEST_TMPDIR/nameprobe"
mkdir -p "$NAME_PROBE_REPO"
git -C "$NAME_PROBE_REPO" init -q
host_can_name() {
  local name="$1" rc=1
  if : >"$NAME_PROBE_REPO/$name" 2>/dev/null && [[ -f "$NAME_PROBE_REPO/$name" ]]; then
    if git -C "$NAME_PROBE_REPO" status --porcelain -z 2>/dev/null |
      tr '\0' '\n' | grep -qxF "?? $name"; then
      rc=0
    fi
  fi
  rm -f -- "$NAME_PROBE_REPO/$name" 2>/dev/null
  return "$rc"
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
# A spaced path arrives C-quoted, and whitespace splitting made it vanish behind a
# reassuring files=0, so the fixture name must contain a space. The arms use separate
# repos so one correctly parsed file cannot keep files= above zero and mask the other.

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

# --- 10. SKILL.md pre-computed-context preview stays at parity with detect.sh (#3126) ----
# A divergence between the SKILL.md preview and the audit is a false negative, so this
# runs the shared script itself after asserting the line still calls it. Fixture names
# force C-quoting with a quote and backslash, since quote-stripping alone passes a space.

SKILL_MD="$SCRIPT_DIR/../SKILL.md"
PREVIEW_SCRIPT="$SCRIPT_DIR/../../../scripts/changed-code-files.sh"
if [[ ! -f "$SKILL_MD" || ! -f "$PREVIEW_SCRIPT" ]]; then
  fail "preview surfaces located for parity check" "SKILL.md and scripts/changed-code-files.sh" "missing"
else
  # shellcheck disable=SC2016  # fixed-string match for the literal ${CLAUDE_SKILL_DIR} in SKILL.md; no expansion wanted.
  # The line goes through the skill-local exec wrapper (repo grant convention, see
  # allowed-tools-pairing.test.sh); it execs the same shared script, so parity holds.
  if ! grep -qF '!`${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh' "$SKILL_MD"; then
    fail "SKILL.md preview line calls the shared script" "a call through \${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh" "line shape changed"
  else
    pass "SKILL.md preview line calls the shared script"

    REPO13="$TEST_TMPDIR/repo13"
    mkdir -p "$REPO13"
    git -C "$REPO13" init -q
    # silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
    if host_can_name 'quote".py'; then : >"$REPO13/quote\".py"; fi
    # silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
    if host_can_name 'back\-slash.py'; then : >"$REPO13/back\\-slash.py"; fi
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

    skill_out="$(cd "$REPO13" && bash "$PREVIEW_SCRIPT")"

    assert_contains "preview script reads a non-ASCII path undecoded" "$skill_out" 'café.py'
    assert_not_contains "preview script leaks no octal escape" "$skill_out" '\303'
    # silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
    if host_can_name 'quote".py'; then
      assert_contains "preview script unescapes an embedded quote" "$skill_out" 'quote".py'
    else
      skip "preview script unescapes an embedded quote" \
        'a double quote does not survive into a filename git can see here'
    fi
    # silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
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

    # Parity in BOTH directions: a forward-only check misses an over-reporting preview (drop
    # the awk rename skip and a prefix-offset path naming no file still passes forward). REPO13
    # holds only code files, so the two sets must match exactly.
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

# --- 11. Paths v1 porcelain escapes or renders ambiguously (#3126) ---------------------
# The v1 record cannot be parsed back reliably: git wraps and C-style-escapes any path holding a
# non-ASCII byte, a tab, or a backslash, and its "old -> new" rename rendering is byte-identical
# to an ordinary file literally named "left -> right.py". Reading -z instead removes the encoding
# entirely. Kept in its own repo so REPO13's parity fixture stays untouched.
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

# --- 12. origin-note shape ------------------------------------------------------------

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

# The control goes FIRST: cr_line_skipped suppresses a line when the marker is on it
# OR on the line before it, so a control placed after the inline-marker line would be
# swallowed and the case would pass for the wrong reason.
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

# The cue must open the comment or a clause inside it, and it must be a whole word.
# Without both, `exported from` matches `ported from` and `padded <date>` matches
# `added <date>`, and an ordinary description of runtime behavior becomes a finding.
#
# The last line is the portability pin. `[[ =~ ]]` rejects a bare `;` at parse time, so
# the clause class has to be spelled `[,\;:]`; bash strips that backslash before regcomp
# rather than passing it through as a bracket member. Were a bash version to pass it
# through, a backslash would become a clause opener and this line would fire.
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

# origin-note is tier 1, which reads "remove". A license or attribution header carries
# text the reader may be legally required to keep, and a marker comment is tracked work,
# so neither is an origin note however it opens. The marker test reuses
# cr_is_sanctioned_todo verbatim rather than redefining which markers count, so a marker
# in the TODO(#n) or TODO: form is exempt here exactly as it is for ticket-pr-residue.
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

# The exemption is BLOCK-scoped: a contiguous comment run carrying a license cue anywhere
# in it is exempt whole, because the canonical NOTICE header does not repeat the cue on
# the attribution line. The run ends at a blank line or at code, so the same sentence in
# the next comment run is an ordinary origin note again.
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

# The hash-comment run form, and the run ending at code rather than a blank line.
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

# The license cues are narrow: `copyright` counts beside a (c), a year, or at the start of
# the comment, and `(c)` counts only in front of a year. Otherwise these two ordinary
# comments would be silently exempted.
# A doc-comment leader is decoration, not comment text. Left in place it occupies the
# clause-opening position, so the cue right behind it never anchors.
ORIGIN_LEADER="$TEST_TMPDIR/origin-leader.cs"
cat >"$ORIGIN_LEADER" <<'EOF'
/// Ported from the reference implementation.
//! Ported from the reference implementation.
EOF
origin_leader_out="$(bash "$DETECT" "$ORIGIN_LEADER")"
assert_contains "a /// doc-comment leader does not block the anchor" "$origin_leader_out" "Finding excerpt: /// Ported from the reference implementation."
assert_contains "a //! doc-comment leader does not block the anchor" "$origin_leader_out" "Finding excerpt: //! Ported from the reference implementation."
assert_contains "both doc-comment forms are findings" "$origin_leader_out" "T1=2 T2=0 T3=0"

# The cue needs a terminator at its end, or `from` matches inside `fromage` and a date
# matches inside a longer run of characters.
ORIGIN_TERM="$TEST_TMPDIR/origin-terminator.js"
cat >"$ORIGIN_TERM" <<'EOF'
// ported fromage is a cheese
// Copied fromage shop inventory
// Added 2026-09-011 to the list
// Added 2026-09-01x to the list
EOF
origin_term_out="$(bash "$DETECT" "$ORIGIN_TERM")"
assert_contains "the cue must end on a boundary" "$origin_term_out" "T1=0 T2=0 T3=0"

# The boundary must not swallow an ISO-8601 datetime: the `T` is alphanumeric, so a
# terminator alone would stop a timestamped origin note from matching.
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

# One line can carry two shapes with opposite tiers; both are reported, neither masks
# the other.
ORIGIN_BOTH="$TEST_TMPDIR/origin-both.py"
cat >"$ORIGIN_BOTH" <<'EOF'
# Merged 2026-07-24 from branch feature/x
EOF
origin_both_out="$(bash "$DETECT" "$ORIGIN_BOTH")"
assert_contains "origin-note reports the branch-bearing line" "$origin_both_out" "Finding shape: origin-note"
assert_contains "ticket-pr-residue reports the same line" "$origin_both_out" "Finding shape: ticket-pr-residue"
assert_contains "double-fire is one T1 and one T2" "$origin_both_out" "T1=1 T2=1 T3=0"

# --- 9. Ticket-pr negatives: plain prose must not fire (#4530) -----------------------

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

# --- 10. Cue coverage, word boundaries, bare repo#N, anchored marker exemption ---------

# Each case is one comment line in a throwaway file, so a finding cannot be blamed on a
# neighbour. `expect_shape` wants the shape reported; `expect_clean` wants no finding at all.
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

# Every example in SKILL.md's shapes table is a finding.
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

# Every tier-1 cue is a whole phrase. The negatives sit one character off the cue: a longer
# word behind it, or a longer word in front of it.
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

# The end boundary is a boundary, not a space: punctuation after the cue still fires.
expect_shape "cue followed by punctuation" "used to, until the rewrite" history-narration

# Bare name#N needs a name of at least three characters and a non-alphanumeric character
# before it, so language names with a sharp and a section number are not references. A
# bare (#3126) stays uncounted.
expect_clean "C#7 is not a reference" "C#7 records need the newer compiler"
expect_clean "F# 3 is not a reference" "F# 3 supports type providers"
expect_clean "A#5 is not a reference" "A#5 is a note name"
expect_clean "see section #3 is not a reference" "see section #3"
expect_clean "bare (#3126) is not counted" "fixes the loop (#3126)"

# The marker exemption is anchored: a whole word that opens the comment or a clause and is
# followed by `(` or `:`. A marker mentioned mid-sentence exempts nothing. A marker inside a
# longer word (`TODOS`, `XXXL`) is no marker.
expect_clean "TODO(#n) exempts its ticket ref" "TODO(#123): see PR #45"
expect_clean "TODO: exempts its ticket ref" "TODO: see PR #45"
expect_clean "clause-opening FIXME: exempts" "note; FIXME: from branch x"
expect_shape "marker mentioned mid-sentence exempts nothing" "see PR #45 and the TODO list" ticket-pr-residue
expect_shape "bare TODO without ( or : exempts nothing" "TODO fix, see PR #45" ticket-pr-residue
expect_shape "marker inside a longer word exempts nothing" "TODOS: see PR #45" ticket-pr-residue

# history-narration-weak (tier 2): cues that also open ordinary prose. Each whole-word cue
# fires, the shape is Tier 2, and a longer word on either side of the cue does not.
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

# A comment line that continues a comment on the previous line is also read joined to it. The
# wrapped finding is reported once, at the first line's number.
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

# A phrase on one line is reported once even when a comment line follows it.
wrap_out="$(bash "$DETECT" "$(wrap_fixture once <<'EOF'
# keeps the order as before
# for every caller
EOF
)")"
assert_eq "a single-line finding is not reported again when joined" "1" "$(wrap_count "$wrap_out")"

# Findings on both lines keep line order and each shape is reported once.
wrap_out="$(bash "$DETECT" "$(wrap_fixture both <<'EOF'
# as before, see PR #45
# and the old shared group
EOF
)")"
assert_eq "two lines with own findings give three findings" "3" "$(wrap_count "$wrap_out")"
first_line="$(grep -m1 '^Finding line:' <<<"$wrap_out")"
assert_eq "own findings keep line order" "Finding line: 1" "$first_line"

# No join across code, a blank comment line, or a gap.
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

# A trailing comment on a code line does not continue a comment.
wrap_out="$(bash "$DETECT" "$(wrap_fixture trailing <<'EOF'
# grouped (ci-perf Phase
value = 6  # 6b) ends here
EOF
)")"
assert_contains "code line with a trailing comment starts no join" "$wrap_out" "T1=0 T2=0 T3=0"

# Opt-out markers still hold for a joined finding, on either line and on the line before.
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

# A license block stays exempt from origin-note when the cue wraps.
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

# --- Upstream labels and --exclude-from ---------------------------------------------------

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

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed, %d host skip(s).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed, %d host skip(s).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
