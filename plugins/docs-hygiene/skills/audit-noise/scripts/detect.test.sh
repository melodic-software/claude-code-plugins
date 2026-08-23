#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib — ships with the
# plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

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

Do not use markdown in your response.
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
assert_contains "negation-without-positive finding" "$out" "Finding shape: negation-without-positive"
assert_contains "preamble tier 2" "$out" "Finding tier: 2"
assert_contains "file summary" "$out" "Summary file: $ALL_SHAPES"

# --- 2b. negation-without-positive: tier, and BOTH tier functions -------------------
#
# The shape lands in Tier 2, and asserting it through the emitted record is only
# half the check: detect.sh calls audit_noise_shape_tier_into exclusively, so a
# shape registered in the nameref arm but missed in the printf arm passes every
# end-to-end assertion and silently returns Tier 3 to any other caller. Both
# arms are exercised directly here, against the same expected value.

neg_tier_line="$(bash "$DETECT" "$ALL_SHAPES" | grep -B1 'Finding shape: negation-without-positive' | head -1)"
assert_contains "negation-without-positive is Tier 2 end to end" "$neg_tier_line" "Finding tier: 2"

tier_probe="$(
  # shellcheck source=lib/noise-shapes.sh
  source "$SCRIPT_DIR/lib/noise-shapes.sh"
  t_into=""
  audit_noise_shape_tier_into 'negation-without-positive' t_into
  printf 'into=%s printf=%s' "$t_into" "$(audit_noise_shape_tier 'negation-without-positive')"
)"
assert_contains "both tier functions agree on Tier 2" "$tier_probe" "into=2 printf=2"

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

# --- 12. negation-without-positive: the lines that must NOT be reported --------------
#
# Two distinct no-flag claims, kept apart because they discharge different bars.
#
#   12a PAIRED — the doctrine's own conforming form. A negation that states its
#       positive alternative in the same sentence is what `write-for-agents`
#       asks for, so reporting it would flag compliance as a defect.
#   12b GUARDRAIL — a prohibition that cannot be phrased positively. Deciding
#       that a given guardrail cannot be is a JUDGMENT, which is why the shape
#       is Tier 2 and why an unmarked bare guardrail still emits for a reviewer
#       to rule on. What the scanner owes is a way to make that ruling STICK:
#       the documented opt-out marker, asserted here on exactly such a line.
#       12a alone would not prove this bar — an unpaired guardrail does fire.

NEG_PAIRED="$TEST_TMPDIR/neg-paired.md"
cat >"$NEG_PAIRED" <<'EOF'
# Paired negations keep their negation

Do not use markdown; write smoothly flowing prose paragraphs.

Never force-push to a shared branch — push with `--force-with-lease` to your own.

Avoid deep nesting: prefer an early return.

Do not hand-edit the generated block. Regenerate it instead.

Don't diagnose yet. Just mark.

The script does not read the config file.
EOF

# A capability roster is a SEPARATE claim from pairing — it declines on the
# third-person `-s` test, not because it names an alternative. Keeping it in
# the paired fixture above would have credited 12a with a line it does not
# carry.
NEG_ROSTER="$TEST_TMPDIR/neg-roster.md"
cat >"$NEG_ROSTER" <<'EOF'
# Third-person prose describes; it does not instruct

- Never audits a target that is not a git repository. It refuses.
- Never mutates without presenting the change set.
- Never edits managed policy or a user-scope file, in any mode.
EOF
neg_roster_out="$(bash "$DETECT" "$NEG_ROSTER")"
assert_not_contains "a third-person capability roster is not an instruction" \
  "$neg_roster_out" "Finding shape: negation-without-positive"
assert_contains "capability-roster file is clean" "$neg_roster_out" "| T1=0 T2=0 T3=0"

# The `-s` test is scoped to `Never`: applied to `Avoid` it reads a PLURAL NOUN
# as a third-person verb and drops real imperatives.
NEG_PLURAL="$TEST_TMPDIR/neg-plural.md"
cat >"$NEG_PLURAL" <<'EOF'
# Avoid takes a noun object

Avoid conditions the transcript cannot show.

Avoid abbreviations.
EOF
neg_plural_out="$(bash "$DETECT" "$NEG_PLURAL")"
assert_contains "Avoid + plural noun is still an imperative" "$neg_plural_out" "| T1=0 T2=2 T3=0"
neg_paired_out="$(bash "$DETECT" "$NEG_PAIRED")"
assert_not_contains "a paired negation is not reported" "$neg_paired_out" "Finding shape: negation-without-positive"
assert_contains "paired-negation file is clean" "$neg_paired_out" "| T1=0 T2=0 T3=0"

NEG_GUARD="$TEST_TMPDIR/neg-guardrail.md"
cat >"$NEG_GUARD" <<'EOF'
# A hard guardrail the positive form cannot carry

<!-- markdown-discipline-ignore-line -->
Never force-push to a shared branch.

<!-- markdown-discipline-ignore -->
Never commit a credential to tracked source.
EOF
neg_guard_out="$(bash "$DETECT" "$NEG_GUARD")"
assert_not_contains "a marked hard guardrail is not reported" "$neg_guard_out" "Finding shape: negation-without-positive"
assert_contains "hard-guardrail file is clean" "$neg_guard_out" "| T1=0 T2=0 T3=0"

# Control: BOTH marked lines fire without their markers, so the clean result
# above is the markers doing work rather than two lines that never qualified.
# Without this the paragraph-marker half of 12b passes vacuously.
NEG_GUARD_CTL="$TEST_TMPDIR/neg-guardrail-control.md"
cat >"$NEG_GUARD_CTL" <<'EOF'
# A hard guardrail the positive form cannot carry

Never force-push to a shared branch.

Never commit a credential to tracked source.
EOF
neg_guard_ctl_out="$(bash "$DETECT" "$NEG_GUARD_CTL")"
assert_contains "both guardrail lines fire when unmarked" "$neg_guard_ctl_out" "| T1=0 T2=2 T3=0"

# --- 12c. A transparent adverb only suppresses when something FOLLOWS it -------------
#
# "just", "simply", "then" lead an imperative without being one, so the
# positive-clause test looks THROUGH them to the next word. The trap is the
# dangling case: with nothing after it, an adverb would otherwise fall through
# as if it were the content word it was standing in front of, and silently
# suppress a real finding. Both directions are pinned here because only the
# pair distinguishes "looked through" from "treated as content".

NEG_ADV="$TEST_TMPDIR/neg-adverb.md"
cat >"$NEG_ADV" <<'EOF'
# Dangling adverbs name nothing

Never resolve the thread, just.

Do not stop there, then.
EOF
neg_adv_out="$(bash "$DETECT" "$NEG_ADV")"
assert_contains "a dangling transparent adverb still reports" "$neg_adv_out" "Finding shape: negation-without-positive"
assert_contains "both dangling-adverb lines report" "$neg_adv_out" "| T1=0 T2=2 T3=0"

NEG_ADV_OK="$TEST_TMPDIR/neg-adverb-ok.md"
cat >"$NEG_ADV_OK" <<'EOF'
# An adverb followed by an imperative is a positive alternative

Don't diagnose yet. Just mark.

Never re-run the whole suite. Simply re-run the failing case.
EOF
neg_adv_ok_out="$(bash "$DETECT" "$NEG_ADV_OK")"
assert_not_contains "an adverb-led imperative suppresses" "$neg_adv_ok_out" "Finding shape: negation-without-positive"
assert_contains "adverb-led-imperative file is clean" "$neg_adv_ok_out" "| T1=0 T2=0 T3=0"

# --- 13. negation-without-positive: no remediation touches a trigger surface ----------
#
# check-skill.sh:414 hard-FAILs a dropped 'trigger phrase' against the base ref,
# so a finding whose Location is a skill's frontmatter would route an edit at the
# one surface that must not move. The scanner cannot emit one: detect.sh skips
# YAML frontmatter wholesale, which is where `description`, `when_to_use` and
# every quoted trigger phrase live. Asserted against a frontmatter carrying all
# three, each a bare negation that would otherwise fire.

# The fixture values must be LINE-INITIAL, or the assertion is vacuous: after
# `description: "` the cue is mid-line and would not fire even as body prose,
# so the test would pass with detect.sh's frontmatter skip deleted outright.
# YAML block scalars put each value on its own line, which is the form that
# actually exercises the skip — verified by mutation (comment out the skip and
# these assertions fail).
NEG_FM="$TEST_TMPDIR/neg-frontmatter.md"
cat >"$NEG_FM" <<'EOF'
---
description: |
  Do not use markdown in your response.
  Use when: 'never force-push', 'avoid deep nesting'.
when_to_use: |
  Never run this on a dirty tree.
---

# Body

Body prose is in scope.
EOF
neg_fm_out="$(bash "$DETECT" "$NEG_FM")"
assert_not_contains "no finding lands in frontmatter (description/when_to_use/triggers)" \
  "$neg_fm_out" "Finding shape: negation-without-positive"
assert_contains "frontmatter-only negations leave the file clean" "$neg_fm_out" "| T1=0 T2=0 T3=0"

# Control proving the fixture is not vacuous: the SAME two lines outside
# frontmatter DO fire, so the clean result above is the skip doing work.
NEG_FM_CTL="$TEST_TMPDIR/neg-frontmatter-control.md"
cat >"$NEG_FM_CTL" <<'EOF'
# Body

Do not use markdown in your response.

Never run this on a dirty tree.
EOF
neg_fm_ctl_out="$(bash "$DETECT" "$NEG_FM_CTL")"
assert_contains "the same lines outside frontmatter DO fire" "$neg_fm_ctl_out" "| T1=0 T2=2 T3=0"

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
