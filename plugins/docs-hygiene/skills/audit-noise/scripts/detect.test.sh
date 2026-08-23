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

ALL_SHAPES="$TEST_TMPDIR/all-shapes.md"
cat >"$ALL_SHAPES" <<'EOF'
# Fixture: every shape

The plan lives at .work/foo-slice/PLAN.md for this effort.

## Why this file exists

Empirically observed 2026-01-01 during the rollout.

The following five skills consume this rule.

- `/skill-a` — does one thing
- `/skill-b` — does another

Path-scoped to `src/**` so it loads there.
EOF

CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
# Clean fixture

Plain prose with no noise shapes. The schema uses .work/<slug>/PLAN.md as a
slot-variable example, which is not a ghost ref. Contract slices land in
docs/topics/<slug>/PLAN.md; session handoffs sit in .work/handoffs/, review
reports in .work/reviews/<branch-slug>/, and running-retro ledgers in
.work/running-retros/; .claude/topic-docs.yaml is the tracked concern file.

## Cross-references

Was renamed to something — exempt section, never flagged.
EOF

OPTOUT="$TEST_TMPDIR/legit-optouts.md"
cat >"$OPTOUT" <<'EOF'
# Opt-out fixture

<!-- markdown-discipline-ignore -->
Empirically observed during the bar-rollout window.

<!-- markdown-discipline-ignore-line -->
We pivoted from the 2026-05-01 incident layout.

<!-- markdown-discipline-ignore -->
First line of a wrapped paragraph with no noise,
was renamed to something on its second line —
paragraph scope must cover every line to the blank.

<!-- markdown-discipline-ignore -->
Marked paragraph followed directly by a heading.
## Heading closes the marker scope
We pivoted from the heading-scope layout.

Path-scoped to `docs/**` per the loader.
EOF

# --- 1. --help contract -----------------------------------------------------------

help_exit=0
bash "$DETECT" --help >/dev/null 2>&1 || help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"

unknown_exit=0
bash "$DETECT" --bogus >/dev/null 2>&1 || unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"

# --- 2. All shapes detected --------------------------------------------------------

out="$(bash "$DETECT" "$ALL_SHAPES")"
assert_contains "ghost-ref finding" "$out" "Finding shape: ghost-ref"
assert_contains "citation finding" "$out" "Finding shape: citation"
assert_contains "enum-list finding" "$out" "Finding shape: enum-list"
assert_contains "scope-meta finding" "$out" "Finding shape: scope-meta"
assert_contains "preamble finding" "$out" "Finding shape: preamble"
assert_contains "preamble tier 2" "$out" "Finding tier: 2"
assert_contains "file summary" "$out" "Summary file: $ALL_SHAPES"

# --- 3. Clean fixture: slot-variable not flagged; exempt section skipped -----------

clean_out="$(bash "$DETECT" "$CLEAN")"
assert_contains "clean summary present" "$clean_out" "Summary total:"
assert_not_contains "slot-variable not a ghost ref" "$clean_out" "Finding shape: ghost-ref"
assert_not_contains "exempt section suppressed" "$clean_out" "Finding shape: citation"

# --- 4. Opt-out markers suppress wrapped content ------------------------------------

opt_out="$(bash "$DETECT" "$OPTOUT")"
assert_not_contains "opt-out citation suppressed" "$opt_out" "bar-rollout"
assert_not_contains "opt-out line suppressed" "$opt_out" "2026-05-01 incident"
assert_not_contains "opt-out paragraph scope covers wrapped lines" "$opt_out" "was renamed to something on its second"
assert_contains "heading ends marker scope even without a blank" "$opt_out" "heading-scope layout"
assert_contains "scope-meta still detected" "$opt_out" "Finding shape: scope-meta"

# --- 5. Backtick-wrapped slash-command roster detected ------------------------------

BT_FIXTURE="$TEST_TMPDIR/bt.md"
cat >"$BT_FIXTURE" <<'EOF'
- `/skill-z` — backtick-wrapped slash command
EOF
bt_out="$(bash "$DETECT" "$BT_FIXTURE")"
assert_contains "backtick enum-list detected" "$bt_out" "Finding shape: enum-list"

# --- 5b. CHANGELOG.md skipped by basename (exempt per SKILL.md hard rules) ----------

CL_FIXTURE="$TEST_TMPDIR/CHANGELOG.md"
cat >"$CL_FIXTURE" <<'EOF'
# Changelog

Was renamed to something. Empirically observed. `.work/some-slice/PLAN.md` cited.
EOF
cl_out="$(bash "$DETECT" "$CL_FIXTURE")"
assert_not_contains "CHANGELOG.md emits no findings" "$cl_out" "Finding shape:"
assert_not_contains "CHANGELOG.md not counted as audited" "$cl_out" "Summary file: $CL_FIXTURE"

# --- 6. Directory target expands to its .md files ------------------------------------

DIR_FIXTURE="$TEST_TMPDIR/dir-target/nested"
mkdir -p "$DIR_FIXTURE"
cp "$ALL_SHAPES" "$DIR_FIXTURE/inner.md"
dir_out="$(bash "$DETECT" "$TEST_TMPDIR/dir-target")"
assert_contains "directory target audits nested .md" "$dir_out" "Summary file: $DIR_FIXTURE/inner.md"
assert_contains "directory target finds shapes" "$dir_out" "Finding shape: ghost-ref"

# --- 7. --paths-file input ----------------------------------------------------------

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$CLEAN" >"$PATHS"
pf_out="$(bash "$DETECT" --paths-file "$PATHS")"
assert_contains "paths-file target audited" "$pf_out" "Summary file: $CLEAN"

# --- 8. Topic-docs taxonomy: concrete contract slice flags; convention forms pass ----

TAXONOMY="$TEST_TMPDIR/taxonomy.md"
cat >"$TAXONOMY" <<'EOF'
# Taxonomy fixture

The worked example lives at docs/topics/net-hardening/PLAN.md on the branch.
EOF
tax_out="$(bash "$DETECT" "$TAXONOMY")"
assert_contains "concrete contract-slice path is a ghost ref" "$tax_out" "Finding shape: ghost-ref"

# --- 9. Retired .claude artifact locations always flag -------------------------------

NOTES="$TEST_TMPDIR/notes.md"
cat >"$NOTES" <<'EOF'
# Notes fixture

Older drafts sit under .claude/notes/net-hardening/ for this rule.
EOF
notes_out="$(bash "$DETECT" "$NOTES")"
assert_contains "retired .claude/notes/ citation flags" "$notes_out" "Finding shape: ghost-ref"

MIGRATE="$TEST_TMPDIR/migrate.md"
cat >"$MIGRATE" <<'EOF'
# Migration fixture

Move .claude/notes/<slug>/ content into .work/<slug>/ before the sunset.
EOF
mig_out="$(bash "$DETECT" "$MIGRATE")"
assert_contains ".claude/notes/ flags even beside convention placeholders" "$mig_out" "Finding shape: ghost-ref"

HANDOFFS="$TEST_TMPDIR/retired-handoffs.md"
cat >"$HANDOFFS" <<'EOF'
# Retired handoffs fixture

Prior save-points sit under .claude/handoffs/<timestamp>-handoff-<topic>.md.
EOF
handoffs_out="$(bash "$DETECT" "$HANDOFFS")"
assert_contains "retired .claude/handoffs/ citation flags" "$handoffs_out" "Finding shape: ghost-ref"

REVIEW="$TEST_TMPDIR/retired-review.md"
cat >"$REVIEW" <<'EOF'
# Retired review fixture

Prior findings sit under .claude/review/<branch-slug>/self.md.
EOF
review_out="$(bash "$DETECT" "$REVIEW")"
assert_contains "retired .claude/review/ citation flags" "$review_out" "Finding shape: ghost-ref"

# --- 10. Per-match exemption: convention tokens never mask concrete ghost refs --------

MIXED="$TEST_TMPDIR/mixed-line.md"
cat >"$MIXED" <<'EOF'
# Mixed-line fixture

See docs/topics/auth-fix/PLAN.md and the concern file .claude/topic-docs.yaml for detail.
EOF
mixed_out="$(bash "$DETECT" "$MIXED")"
assert_contains "concern-file token does not exempt a concrete slice on the same line" "$mixed_out" "Finding shape: ghost-ref"

DEEP="$TEST_TMPDIR/deep-review.md"
cat >"$DEEP" <<'EOF'
# Deep-review fixture

Review report kept at .work/reviews/pr-123-auth/20260101T000000Z-self.md for posterity.
EOF
deep_out="$(bash "$DETECT" "$DEEP")"
assert_contains "concrete child under .work/reviews/ is a ghost ref" "$deep_out" "Finding shape: ghost-ref"

DIGIT="$TEST_TMPDIR/digit-slug.md"
cat >"$DIGIT" <<'EOF'
# Digit-slug fixture

Plan lives at docs/topics/2026-migration/PLAN.md today.
EOF
digit_out="$(bash "$DETECT" "$DIGIT")"
assert_contains "digit-leading slug is a ghost ref" "$digit_out" "Finding shape: ghost-ref"

UNDERSCORE="$TEST_TMPDIR/underscore-child.md"
cat >"$UNDERSCORE" <<'EOF'
# Underscore-child fixture

Report kept at .work/reviews/_hotfix/20260101T000000Z-self.md for posterity.
EOF
underscore_out="$(bash "$DETECT" "$UNDERSCORE")"
assert_contains "underscore-leading child under a concern root is a ghost ref" "$underscore_out" "Finding shape: ghost-ref"

BARE_ROOT="$TEST_TMPDIR/bare-root.md"
cat >"$BARE_ROOT" <<'EOF'
# Bare-root fixture

.work/reviews/ is self-ignoring
.work/running-retros/ holds session ledgers
The ledgers live in .work/running-retros/.
EOF
bare_out="$(bash "$DETECT" "$BARE_ROOT")"
assert_not_contains "bare concern root is not a ghost ref" "$bare_out" "Finding shape: ghost-ref"
assert_not_contains "bare concern root with terminal period stays exempt" "$bare_out" "Finding shape: ghost-ref"

RUNNING_RETRO_CHILD="$TEST_TMPDIR/running-retro-child.md"
cat >"$RUNNING_RETRO_CHILD" <<'EOF'
# Running-retro child fixture

Ledger kept at .work/running-retros/20260101T000000Z-running-retro-auth.md for posterity.
EOF
rr_out="$(bash "$DETECT" "$RUNNING_RETRO_CHILD")"
assert_contains "concrete child under .work/running-retros/ is a ghost ref" "$rr_out" "Finding shape: ghost-ref"

OVERENG_BARE="$TEST_TMPDIR/overengineering-bare.md"
cat >"$OVERENG_BARE" <<'EOF'
# Overengineering bare-root fixture

Findings live under .work/overengineering/ on the auditing branch.
EOF
oe_bare_out="$(bash "$DETECT" "$OVERENG_BARE")"
assert_not_contains "bare .work/overengineering/ is not a ghost ref" "$oe_bare_out" "Finding shape: ghost-ref"

OVERENG_CHILD="$TEST_TMPDIR/overengineering-child.md"
cat >"$OVERENG_CHILD" <<'EOF'
# Overengineering child fixture

See .work/overengineering/feat-x/findings.md for the audit ledger.
EOF
oe_child_out="$(bash "$DETECT" "$OVERENG_CHILD")"
assert_contains "concrete child under .work/overengineering/ is a ghost ref" "$oe_child_out" "Finding shape: ghost-ref"

PLACEHOLDER="$TEST_TMPDIR/placeholder.md"
cat >"$PLACEHOLDER" <<'EOF'
# Placeholder fixture

docs/topics/<slug>/PLAN.md
EOF
ph_out="$(bash "$DETECT" "$PLACEHOLDER")"
assert_not_contains "slot-variable placeholder is not a ghost ref" "$ph_out" "Finding shape: ghost-ref"

# --- Configured convention roots (concern file overrides) ---------------------------

CONF_ROOT="$TEST_TMPDIR/configured-repo"
mkdir -p "$CONF_ROOT/.claude"
cat >"$CONF_ROOT/.claude/topic-docs.yaml" <<'EOF'
memory_dir: .scratch
contract_dir: product/topics
EOF
CONFIGURED="$TEST_TMPDIR/configured.md"
cat >"$CONFIGURED" <<'EOF'
# Configured-roots fixture

Plan kept at product/topics/foo/PLAN.md and notes at .scratch/foo/EXPLORE.md.
.scratch/reviews/ is self-ignoring
.scratch/running-retros/ holds session ledgers
EOF
conf_out="$(AUDIT_NOISE_REPO_ROOT="$CONF_ROOT" bash "$DETECT" "$CONFIGURED")"
assert_contains "configured contract root flags concrete slices" "$conf_out" "product/topics/foo/"
assert_contains "configured memory root flags concrete slices" "$conf_out" ".scratch/foo/"
assert_not_contains "configured bare concern root stays exempt" "$conf_out" ".scratch/reviews/"
assert_not_contains "configured bare running-retros root stays exempt" "$conf_out" ".scratch/running-retros/"

# F6 regression: a configured contract root's bare reviews/handoffs child must
# NOT inherit the memory-root exemption. AUDIT_NOISE_CONTRACT_ROOT used to be
# set only inside a command-substitution subshell and lost, so product/topics/
# reviews/ was incorrectly treated like .work/reviews/.
CONF_CONTRACT_BARE="$TEST_TMPDIR/configured-contract-bare.md"
cat >"$CONF_CONTRACT_BARE" <<'EOF'
# Configured-contract bare-root fixture

product/topics/reviews/ must flag — contract roots have no bare-child exemption.
product/topics/handoffs/ likewise.
EOF
conf_bare_out="$(AUDIT_NOISE_REPO_ROOT="$CONF_ROOT" bash "$DETECT" "$CONF_CONTRACT_BARE")"
assert_contains "configured contract bare reviews/ flags (F6)" "$conf_bare_out" "product/topics/reviews/"
assert_contains "configured contract bare handoffs/ flags (F6)" "$conf_bare_out" "product/topics/handoffs/"

# A quoted memory_dir with an interior '#' and a trailing comment: the old
# hand-rolled `${val%%#*}`-first strip truncated this to `.scratch` (dropping
# everything from the interior '#' on, including the closing quote), so the
# configured root never matched. The shared parse-concern-value.sh helper
# resolves quotes before stripping comments, keeping the interior '#'.
CONF_ROOT_QUOTED="$TEST_TMPDIR/configured-repo-quoted"
mkdir -p "$CONF_ROOT_QUOTED/.claude"
cat >"$CONF_ROOT_QUOTED/.claude/topic-docs.yaml" <<'EOF'
memory_dir: ".scratch#dir/"    # trailing comment must not eat the quoted value
EOF
CONFIGURED_QUOTED="$TEST_TMPDIR/configured-quoted.md"
cat >"$CONFIGURED_QUOTED" <<'EOF'
# Configured-roots quoted fixture

Notes at .scratch#dir/foo/EXPLORE.md.
EOF
conf_quoted_out="$(AUDIT_NOISE_REPO_ROOT="$CONF_ROOT_QUOTED" bash "$DETECT" "$CONFIGURED_QUOTED")"
assert_contains "quoted memory_dir with interior # and trailing comment flags concrete slice" \
  "$conf_quoted_out" ".scratch#dir/foo/"

# --- Exemption gaps (frontmatter / marker / fence / section-state) -------------------

FM_FIXTURE="$TEST_TMPDIR/frontmatter.md"
cat >"$FM_FIXTURE" <<'EOF'
---
name: noisy
description: Empirically observed Path-scoped to src/** loads on Read of X
---

# Body

Body prose with no noise shapes.
EOF
fm_out="$(bash "$DETECT" "$FM_FIXTURE")"
assert_not_contains "frontmatter citation not flagged" "$fm_out" "Finding shape: citation"
assert_not_contains "frontmatter scope-meta not flagged" "$fm_out" "Finding shape: scope-meta"

PROSE_MARKER="$TEST_TMPDIR/prose-marker.md"
cat >"$PROSE_MARKER" <<'EOF'
# Prose marker fixture

Hard rules mention markdown-discipline-ignore as a substring; that must not
suppress the next paragraph.

Empirically observed after a prose mention of the marker name.
EOF
prose_out="$(bash "$DETECT" "$PROSE_MARKER")"
assert_contains "prose marker mention does not suppress citation" "$prose_out" "Finding shape: citation"

FENCE_FIXTURE="$TEST_TMPDIR/fence.md"
cat >"$FENCE_FIXTURE" <<'EOF'
# Fence fixture

```text
Empirically observed inside a fence.
Path-scoped to `src/**` in the example.
.work/foo-slice/PLAN.md
```

After the fence Empirically observed in real prose.
EOF
fence_out="$(bash "$DETECT" "$FENCE_FIXTURE")"
assert_not_contains "fenced citation not flagged" "$fence_out" "inside a fence"
assert_not_contains "fenced ghost-ref not flagged" "$fence_out" "foo-slice"
assert_contains "post-fence citation still flagged" "$fence_out" "real prose"

INLINE_FIXTURE="$TEST_TMPDIR/inline-code.md"
cat >"$INLINE_FIXTURE" <<'EOF'
# Inline fixture

Use `Empirically observed` as the shape name in the table.
See `.work/real-slice/PLAN.md` for the live path.
EOF
inline_out="$(bash "$DETECT" "$INLINE_FIXTURE")"
assert_not_contains "inline-code citation example not flagged" "$inline_out" "Finding shape: citation"
assert_contains "backticked live path still ghost-ref" "$inline_out" "Finding shape: ghost-ref"

SECTION_LEAK="$TEST_TMPDIR/section-leak.md"
cat >"$SECTION_LEAK" <<'EOF'
# Section leak fixture

## Sources

Was renamed to something in Sources.

# Body resumes

Was renamed to something after an H1 closed Sources.

### Sources

Was renamed to something under H3 Sources.
EOF
leak_out="$(bash "$DETECT" "$SECTION_LEAK")"
assert_contains "H1 closes Sources exemption" "$leak_out" "after an H1 closed Sources"
assert_not_contains "H3 Sources is exempt" "$leak_out" "under H3 Sources"
assert_not_contains "H2 Sources body stays exempt" "$leak_out" "in Sources"

# --- Chunk affordance: --offset / --limit over the sorted target list ----------------

CHUNK_A="$TEST_TMPDIR/chunk-a.md"
CHUNK_B="$TEST_TMPDIR/chunk-b.md"
CHUNK_C="$TEST_TMPDIR/chunk-c.md"
printf '# a\n\nEmpirically observed in chunk-a.\n' >"$CHUNK_A"
printf '# b\n\nEmpirically observed in chunk-b.\n' >"$CHUNK_B"
printf '# c\n\nEmpirically observed in chunk-c.\n' >"$CHUNK_C"
chunk_out="$(bash "$DETECT" --offset 1 --limit 1 "$CHUNK_A" "$CHUNK_B" "$CHUNK_C")"
assert_contains "chunk selects middle file only" "$chunk_out" "Summary file: $CHUNK_B"
assert_not_contains "chunk skips earlier file" "$chunk_out" "Summary file: $CHUNK_A"
assert_not_contains "chunk skips later file" "$chunk_out" "Summary file: $CHUNK_C"
assert_contains "chunk still emits findings for selected file" "$chunk_out" "chunk-b"

bad_chunk_exit=0
bash "$DETECT" --offset -1 "$CLEAN" >/dev/null 2>&1 || bad_chunk_exit=$?
assert_exit "negative --offset exits 2" 2 "$bad_chunk_exit"

# --- Default-target porcelain parse (#3143) -------------------------------------------
# With no arguments the audit discovers targets from `git status --porcelain`. Two defects
# in that parse dropped files silently — reported as a reassuring files=0 rather than as an
# error. A plain path passes either implementation, so each fixture name must carry the
# specific character that breaks it. The arms live in separate repos on purpose: sharing one
# would let a correctly-parsed file keep files= above zero and mask the other's disappearance.

# A. An ordinary path containing " -> " is NOT a rename and must survive intact. The
# ungated split fired on any record whose path contained the arrow, reducing this file to
# "draft.md" — a name matching nothing on disk.
REPO_ARROW="$TEST_TMPDIR/repo-arrow"
mkdir -p "$REPO_ARROW"
git -C "$REPO_ARROW" init -q
cp "$ALL_SHAPES" "$REPO_ARROW/notes -> draft.md"

arrow_out="$(cd "$REPO_ARROW" && bash "$DETECT")"
assert_not_contains "arrow-in-name default target is not reported as files=0" "$arrow_out" "files=0"
assert_contains "arrow-in-name default target audited whole" "$arrow_out" "Summary file: notes -> draft.md"
assert_contains "arrow-in-name default target finds shapes" "$arrow_out" "Finding shape: scope-meta"

# B. A genuine rename still resolves to the new path — the gate must narrow the split, not
# remove it.
REPO_RENAME="$TEST_TMPDIR/repo-rename"
mkdir -p "$REPO_RENAME"
git -C "$REPO_RENAME" init -q
cp "$ALL_SHAPES" "$REPO_RENAME/original.md"
git -C "$REPO_RENAME" add original.md
git -C "$REPO_RENAME" -c user.email=t@example.com -c user.name=t commit -qm init
git -C "$REPO_RENAME" mv original.md renamed.md

rename_out="$(cd "$REPO_RENAME" && bash "$DETECT")"
assert_contains "renamed default target resolves to the new path" "$rename_out" "Summary file: renamed.md"
assert_not_contains "renamed default target does not audit the old path" "$rename_out" "Summary file: original.md"

# C. Porcelain is XY: a rename staged only as intent-to-add lands in Y, not X
# (`mv old new && git add -N new` emits " R old -> new"). Gating on X alone would leave the
# record unsplit, so the whole "old -> new" string becomes the path and resolves to nothing.
REPO_WT_RENAME="$TEST_TMPDIR/repo-wt-rename"
mkdir -p "$REPO_WT_RENAME"
git -C "$REPO_WT_RENAME" init -q
cp "$ALL_SHAPES" "$REPO_WT_RENAME/old.md"
git -C "$REPO_WT_RENAME" add old.md
git -C "$REPO_WT_RENAME" -c user.email=t@example.com -c user.name=t commit -qm init
mv "$REPO_WT_RENAME/old.md" "$REPO_WT_RENAME/new.md"
git -C "$REPO_WT_RENAME" add -N new.md

wt_rename_out="$(cd "$REPO_WT_RENAME" && bash "$DETECT")"
assert_not_contains "worktree-column rename is not reported as files=0" "$wt_rename_out" "files=0"
assert_contains "worktree-column rename resolves to the new path" "$wt_rename_out" "Summary file: new.md"

# D. Git C-quotes a path for an embedded backslash too. Unescaping \" but not \\ left the
# path as the escaped literal, which resolves to nothing.
REPO_BSLASH="$TEST_TMPDIR/repo-bslash"
mkdir -p "$REPO_BSLASH"
git -C "$REPO_BSLASH" init -q
cp "$ALL_SHAPES" "$REPO_BSLASH/back\\-slash.md"

bslash_out="$(cd "$REPO_BSLASH" && bash "$DETECT")"
assert_not_contains "backslash default target is not reported as files=0" "$bslash_out" "files=0"
assert_contains "backslash default target unescapes to the real path" "$bslash_out" 'Summary file: back\-slash.md'

# E. Interleaved escapes prove the unescape ORDER: \" must run before \\, or the backslash
# pass re-creates a quote the quote pass has already consumed.
REPO_BOTH="$TEST_TMPDIR/repo-both"
mkdir -p "$REPO_BOTH"
git -C "$REPO_BOTH" init -q
cp "$ALL_SHAPES" "$REPO_BOTH/both\\\".md"

both_out="$(cd "$REPO_BOTH" && bash "$DETECT")"
assert_not_contains "interleaved-escape target is not reported as files=0" "$both_out" "files=0"
assert_contains "interleaved-escape target unescapes both forms" "$both_out" 'Summary file: both\".md'

# F. SKILL.md's `Uncommitted .md files:` line previews the same discovery with a grep, not
# with detect.sh's parse. It shares the defect CLASS rather than the code: a C-quoted path
# ends with the closing quote, not `.md`, so `grep '\.md$'` dropped every spaced, arrowed,
# backslashed or quoted markdown file from the preview with no signal. Extracted from
# SKILL.md and executed so the two surfaces cannot drift apart silently.
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
  skill_grep="$(sed -n 's/^Uncommitted \.md files: !`git status --porcelain 2>\/dev\/null | \(grep [^|]*\) | head.*/\1/p' "$SKILL_MD")"
  if [[ -n "$skill_grep" ]]; then
    skill_out="$(cd "$REPO_ARROW" && eval "git status --porcelain | $skill_grep")"
    assert_contains "SKILL.md preview keeps a quoted .md path" "$skill_out" 'notes -> draft.md'
  else
    fail "SKILL.md preview grep is extractable" "a grep expression" "no match in $SKILL_MD"
  fi
else
  fail "SKILL.md exists for parity check" "$SKILL_MD" "missing"
fi

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
