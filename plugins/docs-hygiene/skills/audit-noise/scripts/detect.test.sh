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
# skip_case <reason> — skip one optional case without exiting. Named to match the
# house helper so scripts/check-discriminating-test-skips.sh can see these
# branches; a bare `printf 'SKIP:'` is invisible to that gate. It must never
# swallow the only discriminating coverage for a case group.
skip_case() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP: %s\n' "$1" >&2
}
# fail_discriminating_skip <reason> — a skip that WOULD vacate the only
# discriminating assertions in a case group. Counts as a failure, so a green
# tally can never mean "every proving fixture was skipped".
fail_discriminating_skip() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'DISCRIMINATING SKIP: [%d] %s\n' "$CASE_NUM" "$1" >&2
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

# A longer outer fence wrapping a standard inner fence must stay closed only
# at the matching-or-longer closer. A naive 3+ toggle treats the inner close
# as the outer close and then scans the remaining example as prose.
NESTED_FENCE="$TEST_TMPDIR/nested-fence.md"
cat >"$NESTED_FENCE" <<'EOF'
# Nested fence fixture

````markdown
An example suppression record:

```yaml
reason: "Conflicts with org policy; exception requested, tracked in #482."
```

Empirically observed inside the outer fence after the inner close.
.work/foo-slice/PLAN.md
````

After the outer fence Empirically observed in real prose.
EOF
nested_out="$(bash "$DETECT" "$NESTED_FENCE")"
assert_not_contains "content after an inner fence close stays exempt" \
  "$nested_out" "inside the outer fence"
assert_not_contains "inner-fence ticket residue is not scanned" "$nested_out" "tracked in #482"
assert_not_contains "nested-fence ghost-ref is not scanned" "$nested_out" "foo-slice"
assert_contains "prose after the true outer close still flags" "$nested_out" "real prose"

TILDE_FENCE="$TEST_TMPDIR/tilde-fence.md"
cat >"$TILDE_FENCE" <<'EOF'
# Tilde fence fixture

~~~text
Empirically observed inside a tilde fence.
~~~

After the tilde fence Empirically observed in real prose.
EOF
tilde_out="$(bash "$DETECT" "$TILDE_FENCE")"
assert_not_contains "ordinary tilde fence body stays exempt" "$tilde_out" "inside a tilde fence"
assert_contains "prose after a tilde fence still flags" "$tilde_out" "real prose"

# A fence opening directly after paragraph text flushes the pending negation
# buffer, and that flush runs its own [[ =~ ]] matches. Reading BASH_REMATCH
# for the fence delimiter after the flush aborts the whole run under set -u.
FENCE_AFTER_PROSE="$TEST_TMPDIR/fence-after-prose.md"
cat >"$FENCE_AFTER_PROSE" <<'EOF'
<!-- marker:v1 -->
```json
{ "schema_version": "1.0" }
```
EOF
fence_after_prose_out="$(bash "$DETECT" "$FENCE_AFTER_PROSE" 2>&1)"
fence_after_prose_exit=$?
assert_exit "fence opening after prose does not abort" 0 "$fence_after_prose_exit"
assert_contains "fence opening after prose still summarises" \
  "$fence_after_prose_out" "Summary file: $FENCE_AFTER_PROSE"
assert_not_contains "fence delimiter capture survives the negation flush" \
  "$fence_after_prose_out" "BASH_REMATCH"

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

# --- 11. Prose residue shapes: plan / conversational / tracker ------------------------

RESIDUE="$TEST_TMPDIR/prose-residue.md"
cat >"$RESIDUE" <<'EOF'
# Prose residue fixture

As you asked, this section documents the retry policy.
Per our discussion, the timeout is 30s.
Task 2 replaces the old buffering approach described below.
In this PR we switch the default to streaming.
See PR #45 for the rationale behind the ordering constraint.
Tracked in JIRA-123.
EOF
res_out="$(bash "$DETECT" "$RESIDUE")"
assert_contains "plan-reference detected" "$res_out" "Finding shape: plan-reference"
assert_contains "conversational-antecedent detected" "$res_out" "Finding shape: conversational-antecedent"
assert_contains "ticket-pr-residue detected" "$res_out" "Finding shape: ticket-pr-residue"
assert_contains "plan-reference is tier 1" "$res_out" $'Finding tier: 1\nFinding shape: plan-reference'
assert_contains "conversational-antecedent is tier 1" "$res_out" $'Finding tier: 1\nFinding shape: conversational-antecedent'
assert_contains "ticket-pr-residue is tier 2" "$res_out" $'Finding tier: 2\nFinding shape: ticket-pr-residue'
assert_contains "project-key tracker reference detected" "$res_out" "JIRA-123"
assert_contains "prose residue file summary" "$res_out" "| T1=4 T2=2 T3=0"

# --- 11b. ticket-pr-residue carve-outs: outstanding tracked work ----------------------

CARVEOUT="$TEST_TMPDIR/tracked-work.md"
cat >"$CARVEOUT" <<'EOF'
# Tracked-work fixture

- [ ] Cap the retry budget, see issue 42 for the acceptance test
- [x] Land the streaming default, see issue 43 for the acceptance test
TODO(#123): see issue 44 for the acceptance test.
Bare provenance instead: see issue 45 for the rationale.
EOF
carve_out="$(bash "$DETECT" "$CARVEOUT")"
assert_not_contains "unchecked task-list item is not ticket residue" "$carve_out" "issue 42"
assert_not_contains "checked task-list item is not ticket residue" "$carve_out" "issue 43"
assert_not_contains "tracked-work marker is not ticket residue" "$carve_out" "issue 44"
assert_contains "the same phrasing without a carve-out still flags" "$carve_out" "issue 45"

# --- 11c. Section exemptions cover the prose residue shapes too -----------------------

RES_EXEMPT="$TEST_TMPDIR/residue-exempt.md"
cat >"$RES_EXEMPT" <<'EOF'
# Residue exemption fixture

## Sources

See PR #45 for the rationale behind the ordering constraint.
As you asked, this footer records the provenance.

# Body resumes

As you asked, this line sits outside the exempt section.
EOF
res_ex_out="$(bash "$DETECT" "$RES_EXEMPT")"
assert_not_contains "Sources footer suppresses ticket residue" "$res_ex_out" "ordering constraint"
assert_not_contains "Sources footer suppresses conversational antecedent" "$res_ex_out" "footer records"
assert_contains "residue after the exempt section still flags" "$res_ex_out" "outside the exempt section"

# --- 11d. Prose negatives: the tightenings that keep live prose out ------------------

RES_NEG="$TEST_TMPDIR/prose-negatives.md"
cat >"$RES_NEG" <<'EOF'
# Prose negatives fixture

As we discussed above, the resolver reads the team-tracked file only.
Scope the review to the files changed in this PR before reading further.
Budget deliberation by reversibility tier, per the planning chapter.
The template records what was planned and what was done instead.
The shape definition quotes `As you asked` as its own example.
EOF
res_neg_out="$(bash "$DETECT" "$RES_NEG")"
assert_not_contains "anaphoric cross-reference is not a conversational antecedent" \
  "$res_neg_out" "Finding shape: conversational-antecedent"
assert_not_contains "live 'in this PR' referent is not a plan reference" \
  "$res_neg_out" "Finding shape: plan-reference"
assert_contains "prose negatives file is clean" "$res_neg_out" "| T1=0 T2=0 T3=0"

# --- 11e. conversational-antecedent: passive form and the `in` follower ---------------

ANTE_POS="$TEST_TMPDIR/antecedent-positive.md"
cat >"$ANTE_POS" <<'EOF'
# Antecedent positives fixture

As requested, retry the shard sweep three times.
As we discussed in yesterday's meeting, cap the retry budget.
As we decided in favor of streaming, the buffer is gone.
The change was requested by the operator, so the default flipped.
Fields come back as requested by the client.
EOF
ante_pos_out="$(bash "$DETECT" "$ANTE_POS")"
assert_contains "actor-less 'As requested,' flags" "$ante_pos_out" "retry the shard sweep three times"
assert_contains "'in' ahead of a conversation flags" "$ante_pos_out" "cap the retry budget"
assert_contains "'in favor of' is not a document locator" "$ante_pos_out" "the buffer is gone"
assert_not_contains "'was requested' is not the passive antecedent" "$ante_pos_out" "the default flipped"
assert_not_contains "'as requested by' attribution is not the passive antecedent" \
  "$ante_pos_out" "come back as requested"
assert_contains "antecedent positives count" "$ante_pos_out" "| T1=3 T2=0 T3=0"

ANTE_NEG="$TEST_TMPDIR/antecedent-negative.md"
cat >"$ANTE_NEG" <<'EOF'
# Antecedent exemptions fixture

As we discussed above, the resolver reads the team-tracked file only.
As we agreed Above, follower case does not decide the match.
As we decided in §3, the resolver reads the team-tracked file only.
As we decided in the ADR, the resolver reads the team-tracked file only.
As we decided in the previous section, the resolver reads it.
EOF
ante_neg_out="$(bash "$DETECT" "$ANTE_NEG")"
assert_not_contains "document locators keep the antecedent unflagged" \
  "$ante_neg_out" "Finding shape: conversational-antecedent"
assert_contains "antecedent exemptions file is clean" "$ante_neg_out" "| T1=0 T2=0 T3=0"

# under / at / on used to exempt unconditionally, the same weakness `in` had
# before the locator predicate. Conversational residue phrased with those
# prepositions must flag; a real document locus after them must stay exempt.
# High-traffic `on` idioms that are NOT this shape (based on, depends on, on
# disk, on the other hand) are pinned so narrowing `on` cannot start matching
# ordinary prose that never had an antecedent.
ANTE_PREP="$TEST_TMPDIR/antecedent-prepositions.md"
cat >"$ANTE_PREP" <<'EOF'
# Antecedent preposition fixture

As we agreed on Tuesday, the cap is 30s.
As we decided at the standup, retry three times.
As we agreed under time pressure, this is temporary.
As we decided on the ADR's recommendation, the resolver reads the team file.
The default is based on the measured timeout.
Retry count depends on the shard width.
Persist the snapshot on disk after the write.
On the other hand, keep the current default.
As we discussed above, the resolver reads the team-tracked file only.
EOF
ante_prep_out="$(bash "$DETECT" "$ANTE_PREP")"
assert_contains "'on Tuesday' is conversational residue" "$ante_prep_out" "the cap is 30s"
assert_contains "'at the standup' is conversational residue" "$ante_prep_out" "retry three times"
assert_contains "'under time pressure' is conversational residue" "$ante_prep_out" "this is temporary"
assert_not_contains "'on the ADR' is a document locator" "$ante_prep_out" "the resolver reads the team file"
assert_not_contains "anaphoric 'above' is still a blanket exemption" \
  "$ante_prep_out" "the resolver reads the team-tracked file only"
assert_not_contains "'based on' is not an antecedent" "$ante_prep_out" "measured timeout"
assert_not_contains "'depends on' is not an antecedent" "$ante_prep_out" "shard width"
assert_not_contains "'on disk' is not an antecedent" "$ante_prep_out" "after the write"
assert_not_contains "'on the other hand' is not an antecedent" "$ante_prep_out" "current default"
assert_contains "three new preposition residues and nothing else" "$ante_prep_out" "| T1=3 T2=0 T3=0"

# An inline-code locator the strip removes, followed by punctuation, must
# still count as a document locus after the clause cut — otherwise `on` /
# `at` / `under` newly flag a real path cite.
ANTE_TICK="$TEST_TMPDIR/antecedent-inline-locator.md"
cat >"$ANTE_TICK" <<'EOF'
# Inline-code locator fixture

As we discussed on `docs/design.md`, retain the fallback.
As we decided at `§3`, keep the resolver.
As we agreed under `the ADR`, ship the narrower form.
EOF
ante_tick_out="$(bash "$DETECT" "$ANTE_TICK")"
assert_not_contains "an inline-code locator after on/at/under stays exempt" \
  "$ante_tick_out" "Finding shape: conversational-antecedent"
assert_contains "inline-code locator file is clean" "$ante_tick_out" "| T1=0 T2=0 T3=0"

# --- 11f. Contracted first-person actors, straight and curly apostrophes -------------
# A contraction is the same actor and the same shape; requiring a literal space
# after the pronoun let it escape silently. Both apostrophe forms must work: `’`
# (U+2019) is what most editors produce, and matching only `'` would close half
# the gap while looking fixed.

CONTRACT_POS="$TEST_TMPDIR/contracted-positive.md"
cat >"$CONTRACT_POS" <<'EOF'
# Contracted actors fixture

In this PR we've already switched the default to streaming.
In this PR we’ve already switched the default to streaming.
In this commit I'm switching the default to streaming.
In this commit I’d already switched the default to streaming.
In this PR we’ll switch the default to streaming.
As we've discussed, the timeout is 30s.
As we’ve discussed, the timeout is 30s.
As we'd agreed, the timeout is 30s.
As you’d requested, the timeout is 30s.
EOF
contract_pos_out="$(bash "$DETECT" "$CONTRACT_POS")"
assert_contains "straight-apostrophe plan-reference flags" "$contract_pos_out" "Finding shape: plan-reference"
assert_contains "curly-apostrophe plan-reference flags" "$contract_pos_out" "Finding line: 4"
assert_contains "contracted 'I'm' plan-reference flags" "$contract_pos_out" "Finding line: 5"
assert_contains "curly 'I’d' plan-reference flags" "$contract_pos_out" "Finding line: 6"
assert_contains "curly 'we’ll' plan-reference flags" "$contract_pos_out" "Finding line: 7"
assert_contains "contracted antecedent flags" "$contract_pos_out" "Finding shape: conversational-antecedent"
assert_contains "curly-apostrophe antecedent flags" "$contract_pos_out" "Finding line: 9"
assert_contains "'we'd agreed' antecedent flags" "$contract_pos_out" "Finding line: 10"
assert_contains "curly 'you’d requested' antecedent flags" "$contract_pos_out" "Finding line: 11"
assert_contains "every contracted actor line flags" "$contract_pos_out" "| T1=9 T2=0 T3=0"

# The follower test still runs behind a contraction: widening the actor must not
# smuggle past the document-locator and anaphoric-adverb stand-downs.
CONTRACT_FOLLOWER="$TEST_TMPDIR/contracted-follower.md"
cat >"$CONTRACT_FOLLOWER" <<'EOF'
# Contracted follower fixture

As we've discussed above, the resolver reads the team-tracked file only.
As we’ve decided in §3, the resolver reads the team-tracked file only.
As we'd agreed in the ADR, the resolver reads the team-tracked file only.
EOF
contract_fol_out="$(bash "$DETECT" "$CONTRACT_FOLLOWER")"
assert_not_contains "anaphoric follower still stands a contracted antecedent down" \
  "$contract_fol_out" "Finding shape: conversational-antecedent"
assert_contains "contracted follower file is clean" "$contract_fol_out" "| T1=0 T2=0 T3=0"

# Negatives: widening the actor must add no new false-positive surface. `'re` is
# deliberately absent from the antecedent set — its follower is a past
# participle, and "as you're asked" is a present-tense passive addressing the
# reader generically, not a pointer at a prior exchange.
CONTRACT_NEG="$TEST_TMPDIR/contracted-negative.md"
cat >"$CONTRACT_NEG" <<'EOF'
# Contracted negatives fixture

Do it as you're asked to, then record the result.
Do it as you’re asked to, then record the result.
Scope the review to the files we've changed in this PR before reading further.
The weave is the same as we'd expect from the sibling detector.
EOF
contract_neg_out="$(bash "$DETECT" "$CONTRACT_NEG")"
assert_not_contains "\"as you're asked\" passive is not an antecedent" \
  "$contract_neg_out" "Finding shape: conversational-antecedent"
assert_not_contains "contracted actor after a live 'in this PR' referent is not a plan reference" \
  "$contract_neg_out" "Finding shape: plan-reference"
assert_contains "contracted negatives file is clean" "$contract_neg_out" "| T1=0 T2=0 T3=0"

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

# --- Porcelain discovery: tricky paths survive the parse (#3143 / #3164) --------------
# A plain path passes either implementation, so each case below needs a path git
# treats specially: one containing a literal " -> ", and one containing a backslash.

PORC_REPO="$TEST_TMPDIR/porcelain-repo"
mkdir -p "$PORC_REPO"
git -C "$PORC_REPO" init -q
git -C "$PORC_REPO" config user.email fixture@example.invalid
git -C "$PORC_REPO" config user.name fixture

# Every case below needs a name the local filesystem may refuse, and a redirect to
# such a name does not always fail: Windows substitutes a private-use codepoint for
# '>' and drops a tab, reporting success, and the shell's own -f test then sees the
# same substituted name and agrees the fixture is there. Only git's byte-exact view
# of the worktree can confirm the intended name landed. Without this guard a case
# fails — or worse, passes — for a reason that has nothing to do with the parse.
# Caveats, since this gates whether a case runs at all: it is a substring match over
# the whole status, not an exact record match; it requires the fixture to still be
# DIRTY, so it returns false after the fixture is committed; and it reads the same
# `-z` interface under test, so a `-z` regression would turn assertions into skips
# rather than failures. The skip tally and the esc_discriminators guard below exist
# so that degradation cannot pass silently.
fixture_landed() { # <repo> <intended-name>
  git -C "$1" status --porcelain -z 2>/dev/null | tr '\0' '\n' | grep -qF -- "$2"
}

printf '# plain\n\nEmpirically observed in the plain file.\n' >"$PORC_REPO/plain.md"

printf '# arrow\n\nEmpirically observed in the arrow file.\n' >"$PORC_REPO/notes -> draft.md" 2>/dev/null || true
if fixture_landed "$PORC_REPO" 'notes -> draft.md'; then
  porc_out="$(cd "$PORC_REPO" && bash "$DETECT" 2>/dev/null)"
  assert_contains "untracked path containing ' -> ' is not split as a rename" "$porc_out" "notes -> draft.md"
else
  # discriminating-skip-ok: regression guard for #3171's arrow gate, not a #3164
  # discriminator — the -z read matches no arrow at all, so nothing here proves
  # the fix under test.
  find "$PORC_REPO" -maxdepth 1 -name '*draft.md' -delete 2>/dev/null
  skip_case "filesystem rejects an arrow in a filename"
fi

porc_out="$(cd "$PORC_REPO" && bash "$DETECT" 2>/dev/null)"
assert_contains "ordinary untracked path still discovered" "$porc_out" "plain.md"

# The gate must not cost us real renames: a genuine R record still yields the NEW path.
printf '# renamed\n\nEmpirically observed in the renamed file.\n' >"$PORC_REPO/before.md"
git -C "$PORC_REPO" add before.md
git -C "$PORC_REPO" commit -qm 'seed rename fixture'
git -C "$PORC_REPO" mv before.md after.md
rename_out="$(cd "$PORC_REPO" && bash "$DETECT" 2>/dev/null)"
assert_contains "rename record resolves to the new path" "$rename_out" "after.md"
assert_not_contains "rename record does not keep the old path" "$rename_out" "before.md"

# git C-quotes a path containing a backslash, so that escape must not survive either.
printf '# backslash\n\nEmpirically observed in the backslash file.\n' >"$PORC_REPO/back\\-slash.md" 2>/dev/null || true
if fixture_landed "$PORC_REPO" 'back\-slash.md'; then
  bs_out="$(cd "$PORC_REPO" && bash "$DETECT" 2>/dev/null)"
  assert_contains "backslash path is unescaped and discovered" "$bs_out" 'back\-slash.md'
else
  # discriminating-skip-ok: regression guard for #3171's `\\` unescape, not a
  # #3164 discriminator — the -z read never unescapes anything.
  find "$PORC_REPO" -maxdepth 1 -name '*slash.md' -delete 2>/dev/null
  skip_case "filesystem rejects a backslash in a filename"
fi

# --- negation shape ------------------------------------------------------------------

NEG="$TEST_TMPDIR/negation.md"
cat >"$NEG" <<'EOF'
# Negation fixture

Do not use markdown in your response.

Never call the tool directly.

Avoid restating the rule in the body.

The agent must not emit a bare summary.
EOF
neg_out="$(bash "$DETECT" "$NEG")"
assert_contains "bare prohibition is a negation finding" "$neg_out" "Finding shape: negation"
assert_contains "negation is Tier 2 (its treatment includes an edit)" "$neg_out" "Finding tier: 2"
neg_count="$(printf '%s\n' "$neg_out" | grep -c '^Finding shape: negation')"
# THREE, not four. The fixture's fourth line is subject-led ("The agent must
# not…"), so the imperative-only scope gate declines it — the rule is about
# instructions, and a subject-led sentence is prose describing a component. The
# count is asserted rather than the shape alone so a future widening of that
# gate cannot pass silently.
assert_contains "only the three IMPERATIVE prohibitions flag" "count=$neg_count" "count=3"
assert_not_contains "a subject-led prohibition is out of scope" "$neg_out" "must not emit a bare summary"

# A paired positive in the same sentence is evidence the rule is satisfied.
PAIRED="$TEST_TMPDIR/negation-paired.md"
cat >"$PAIRED" <<'EOF'
# Paired fixture

Do not use markdown; instead compose smoothly flowing prose paragraphs.

Never hardcode the roster — prefer a category citation.

Use a durable pointer in place of a slice path.

Report the cause rather than the symptom.
EOF
paired_out="$(bash "$DETECT" "$PAIRED")"
assert_not_contains "a paired positive suppresses the finding" "$paired_out" "Finding shape: negation"

# A positive supplied as a bare imperative after a separator carries none of
# the marker words, so a marker-list pairing miss-reports it. The closed
# function-word stoplist recognises the clause by what it is NOT. A leading
# adverb is looked through rather than treated as the clause head.
BARE_IMP="$TEST_TMPDIR/negation-bare-imperative.md"
cat >"$BARE_IMP" <<'EOF'
# Bare-imperative pairing fixture

Never confirm a load-bearing deletion from this context — delegate to a fresh, non-fork subagent that has not seen the doc.

Never emit a bare summary — just mark the row.

Do not use markdown; compose flowing prose.

Never confirm the deletion: ask a fresh subagent.
EOF
bare_imp_out="$(bash "$DETECT" "$BARE_IMP")"
assert_not_contains "a bare imperative after an em-dash suppresses the finding" \
  "$bare_imp_out" "Finding shape: negation"

# Consequence / function-word clauses are not alternatives, and a transparent
# adverb with nothing after it names no alternative either.
BARE_IMP_NEG="$TEST_TMPDIR/negation-bare-imperative-neg.md"
cat >"$BARE_IMP_NEG" <<'EOF'
# Bare-imperative still-a-finding fixture

Never confirm a load-bearing deletion from this context.

Never emit a bare summary — because the log is huge.

Never emit a bare summary, just.
EOF
bare_imp_neg_out="$(bash "$DETECT" "$BARE_IMP_NEG")"
bare_imp_neg_count="$(printf '%s\n' "$bare_imp_neg_out" | grep -c '^Finding shape: negation')"
assert_contains "unpaired and function-word clauses still flag" \
  "count=$bare_imp_neg_count" "count=3"

# A second prohibition is not a positive alternative.
BARE_IMP_TWO="$TEST_TMPDIR/negation-two-prohibitions.md"
cat >"$BARE_IMP_TWO" <<'EOF'
# Two-prohibition fixture

Never call the tool directly; avoid invoking its wrapper.
EOF
bare_imp_two_out="$(bash "$DETECT" "$BARE_IMP_TWO")"
assert_contains "a second prohibition is not a paired positive" \
  "$bare_imp_two_out" "Finding shape: negation"

# NO-FLAG TEST: a hard guardrail that cannot be phrased positively is not a
# finding. The prohibition IS the correct form for these.
GUARD="$TEST_TMPDIR/negation-guardrail.md"
cat >"$GUARD" <<'EOF'
# Guardrail fixture

Never commit a secret to the repository.

Do not force-push to a shared branch.

Never run rm -rf against a production checkout.

Do not rewrite history on someone else's branch.

Never log a credential or an api key.
EOF
guard_out="$(bash "$DETECT" "$GUARD")"
assert_not_contains "hard guardrails are never flagged" "$guard_out" "Finding shape: negation"

# The guardrail marker is frequently the inline-code span itself, so the shape
# must read the UNWRAPPED line — stripping the span would erase the evidence
# and turn a guardrail into a false finding.
GUARD_TICKS="$TEST_TMPDIR/negation-guardrail-ticks.md"
cat >"$GUARD_TICKS" <<'EOF'
# Guardrail-in-backticks fixture

Never pass `--force` to that command.
EOF
gt_out="$(bash "$DETECT" "$GUARD_TICKS")"
assert_not_contains "a backticked guardrail marker still carves out" "$gt_out" "Finding shape: negation"

# A before/after demonstration is a worked example, not an instruction.
EXAMPLE="$TEST_TMPDIR/negation-example.md"
cat >"$EXAMPLE" <<'EOF'
# Worked-example fixture

Do not use markdown -> compose flowing prose paragraphs.
EOF
ex_out="$(bash "$DETECT" "$EXAMPLE")"
assert_not_contains "a worked example is not a finding" "$ex_out" "Finding shape: negation"

# Frontmatter is body-scoped out: no candidate may point at a description.
NEG_FM="$TEST_TMPDIR/negation-frontmatter.md"
cat >"$NEG_FM" <<'EOF'
---
description: "Do not use markdown. Never call the tool directly."
---

# Frontmatter fixture

Body prose with no prohibition at all.
EOF
fm_out="$(bash "$DETECT" "$NEG_FM")"
assert_not_contains "frontmatter prohibitions never flag" "$fm_out" "Finding shape: negation"

# SUBSTRING COLLISIONS ON THE WITHHOLDING BOUNDARIES. Both carve-outs suppress a
# candidate, so an unfenced alternative that matches inside a longer word loses a
# real finding SILENTLY — the direction this rule set exists to avoid. Each
# alternative is fenced by non-alphanumeric boundaries; these are the cases that
# regress if a future edit drops one.
NEG_SUBSTR="$TEST_TMPDIR/negation-substrings.md"
cat >"$NEG_SUBSTR" <<'EOF'
# Substring-collision fixture

Do not preferentially select the first item.

Do not send it to the secretary.

Never tokenize the payload by hand.
EOF
substr_out="$(bash "$DETECT" "$NEG_SUBSTR")"
substr_count="$(printf '%s\n' "$substr_out" | grep -c '^Finding shape: negation')"
assert_contains "a longer word never satisfies a withholding marker" "count=$substr_count" "count=3"

# The contraction wildcard must be an apostrophe CLASS: a bare `.` matches
# `donut`, emitting ordinary prose as a Tier 2 finding.
NEG_DONUT="$TEST_TMPDIR/negation-donut.md"
cat >"$NEG_DONUT" <<'EOF'
# Contraction fixture

Choose a donut for breakfast.

The shouldnt token is not a contraction either.
EOF
donut_out="$(bash "$DETECT" "$NEG_DONUT")"
assert_not_contains "a word containing the contraction letters is not a prohibition" "$donut_out" "Finding shape: negation"

APOS="$TEST_TMPDIR/negation-apostrophe.md"
cat >"$APOS" <<'EOF'
# Apostrophe fixture

Don't add a preamble.
EOF
apos_out="$(bash "$DETECT" "$APOS")"
assert_contains "a real contraction still flags" "$apos_out" "Finding shape: negation"

# The reported marker comes from the sentence that TRIGGERED, not the first
# prohibition on the line — otherwise a carved-out leading sentence points
# review at the guardrail instead of the finding.
NEG_MARKER="$TEST_TMPDIR/negation-marker.md"
cat >"$NEG_MARKER" <<'EOF'
# Marker fixture

Never commit a secret. Do not use markdown.
EOF
marker_out="$(bash "$DETECT" "$NEG_MARKER")"
assert_contains "marker comes from the triggering sentence" "$marker_out" "Finding marker: do not"
assert_not_contains "marker is not the carved-out sentence's" "$marker_out" "Finding marker: never"

# SENTENCE SPLITTING AROUND AN EMBEDDED ABBREVIATION. A left-anchored splitter
# cannot skip a period that is not followed by whitespace, so the whole line
# collapses into one "sentence" and a carve-out word in an EARLIER clause
# suppresses a real prohibition in a later one — a silent withhold. The
# right-to-left peel makes an abbreviation over-split instead, which only
# narrows the window a suppressing marker acts from.
# The line is IMPERATIVE and sentence-final so it clears the scope gates, and
# carries an abbreviation plus a guardrail word ahead of a second, bare
# prohibition — which is what puts the splitter under test rather than the gates.
NEG_ABBREV="$TEST_TMPDIR/negation-abbrev.md"
cat >"$NEG_ABBREV" <<'EOF'
# Abbreviation fixture

Never store an api key, e.g. a deploy token, in the repo. Do not use markdown.
EOF
abbrev_out="$(bash "$DETECT" "$NEG_ABBREV")"
assert_contains "a guardrail word in an earlier clause cannot suppress a later prohibition" \
  "$abbrev_out" "Finding shape: negation"
assert_contains "and the marker is the later sentence's" "$abbrev_out" "Finding marker: do not"

# The carve-out must still hold when the guardrail really is in the SAME
# sentence — the split fix must not turn every guardrail into a finding.
NEG_SAME="$TEST_TMPDIR/negation-same-sentence.md"
cat >"$NEG_SAME" <<'EOF'
# Same-sentence guardrail fixture

Never commit a credential to the repository.
EOF
same_out="$(bash "$DETECT" "$NEG_SAME")"
assert_not_contains "a same-sentence guardrail still carves out" "$same_out" "Finding shape: negation"

# SCOPE GATES. "Prompt the positive" is a rule about INSTRUCTIONS, so only an
# imperative selects, and only a line that closes its own sentence can be shown
# to lack a positive. Without both gates the shape fired 1053 times on an
# 85-file sample of this repo (99% of all findings); with them, 31.
NEG_SCOPE="$TEST_TMPDIR/negation-scope.md"
cat >"$NEG_SCOPE" <<'EOF'
# Scope fixture

The config never loads on a cold start.

Older versions do not support this flag.

The scanner should not be confused with a linter.

Prefer a runtime derivation; never hardcode the roster.

| Do not use markdown. | rewrite to the positive |
EOF
scope_out="$(bash "$DETECT" "$NEG_SCOPE")"
assert_not_contains "descriptive prose and mid-sentence cues are out of scope" \
  "$scope_out" "Finding shape: negation"

# The gates must not cost the ordinary imperative forms this rule exists for,
# including the marked-up ones — a list item and a fully bolded directive.
NEG_FORMS="$TEST_TMPDIR/negation-forms.md"
cat >"$NEG_FORMS" <<'EOF'
# Imperative forms fixture

Do not use markdown in your response.

- Never call the tool directly.

**Avoid restating the rule in the body.**

> Do not emit a bare summary.
EOF
forms_out="$(bash "$DETECT" "$NEG_FORMS")"
forms_count="$(printf '%s\n' "$forms_out" | grep -c '^Finding shape: negation')"
assert_contains "plain, list, bolded and blockquoted imperatives all still flag" \
  "count=$forms_count" "count=4"

# Soft-wrapped sentences are accumulated before the classifier runs. A positive
# on the continuation line pairs the sentence; a wrap with no positive must
# flag, attributed to the first physical line of the sentence (where the cue
# opens). The older line-scoped gate withheld the unpaired wrap.
NEG_WRAP_PAIRED="$TEST_TMPDIR/negation-wrap-paired.md"
cat >"$NEG_WRAP_PAIRED" <<'EOF'
# Wrapped paired fixture

Do not use markdown;
compose flowing prose instead.
EOF
wrap_paired_out="$(bash "$DETECT" "$NEG_WRAP_PAIRED")"
assert_not_contains "a wrapped sentence with its positive on the next line is not flagged" \
  "$wrap_paired_out" "Finding shape: negation"

NEG_WRAP_BARE="$TEST_TMPDIR/negation-wrap-bare.md"
cat >"$NEG_WRAP_BARE" <<'EOF'
# Wrapped bare fixture

Do not use markdown
in the summary body.
EOF
wrap_bare_out="$(bash "$DETECT" "$NEG_WRAP_BARE")"
assert_contains "a wrapped sentence with no positive is flagged" \
  "$wrap_bare_out" "Finding shape: negation"
assert_contains "and is attributed to the first line of the sentence" \
  "$wrap_bare_out" $'Finding shape: negation\nFinding line: 3'

NEG_WRAP_CTRL="$TEST_TMPDIR/negation-wrap-control.md"
cat >"$NEG_WRAP_CTRL" <<'EOF'
# Unwrapped control

Never emit a bare summary.
EOF
wrap_ctrl_out="$(bash "$DETECT" "$NEG_WRAP_CTRL")"
assert_contains "an unwrapped imperative still flags" \
  "$wrap_ctrl_out" "Finding shape: negation"

# The other shapes stay line-scoped: joining would invent a citation that no
# physical line actually contains.
LINE_SCOPED="$TEST_TMPDIR/negation-line-scoped-sibling.md"
cat >"$LINE_SCOPED" <<'EOF'
# Line-scoped sibling fixture

Empirically
observed inside a wrap that would match if joined.
EOF
line_scoped_out="$(bash "$DETECT" "$LINE_SCOPED")"
assert_not_contains "citation does not accumulate across a soft wrap" \
  "$line_scoped_out" "Finding shape: citation"

# Frontmatter, fences and opt-out markers still bound accumulation: a wrapped
# prohibition inside any of them must not join a later body sentence.
NEG_FENCE_WRAP="$TEST_TMPDIR/negation-fence-wrap.md"
cat >"$NEG_FENCE_WRAP" <<'EOF'
# Fence-bounded wrap

```text
Do not use markdown
in the fenced body.
```

Do not use markdown
in the summary body.
EOF
fence_wrap_out="$(bash "$DETECT" "$NEG_FENCE_WRAP")"
fence_wrap_count="$(printf '%s\n' "$fence_wrap_out" | grep -c '^Finding shape: negation')"
assert_contains "a fenced wrap is skipped and the body wrap still flags once" \
  "count=$fence_wrap_count" "count=1"
assert_contains "the body wrap is attributed past the fence" \
  "$fence_wrap_out" $'Finding shape: negation\nFinding line: 8'

NEG_IGNORE_WRAP="$TEST_TMPDIR/negation-ignore-wrap.md"
cat >"$NEG_IGNORE_WRAP" <<'EOF'
# Opt-out-bounded wrap

<!-- markdown-discipline-ignore -->
Do not use markdown
in the ignored paragraph.

Do not use markdown
in the summary body.
EOF
ignore_wrap_out="$(bash "$DETECT" "$NEG_IGNORE_WRAP")"
ignore_wrap_count="$(printf '%s\n' "$ignore_wrap_out" | grep -c '^Finding shape: negation')"
assert_contains "an ignored wrap is skipped and the body wrap still flags once" \
  "count=$ignore_wrap_count" "count=1"

# Every qualifying sentence in one paragraph is a finding, attributed to its
# own first physical line. Returning after the first match would drop the
# second imperative.
NEG_TWO_WRAP="$TEST_TMPDIR/negation-two-in-paragraph.md"
cat >"$NEG_TWO_WRAP" <<'EOF'
# Two-sentence paragraph

Do not use markdown.
Never include XML.
EOF
two_wrap_out="$(bash "$DETECT" "$NEG_TWO_WRAP")"
two_wrap_count="$(printf '%s\n' "$two_wrap_out" | grep -c '^Finding shape: negation')"
assert_contains "each imperative sentence in a paragraph flags" \
  "count=$two_wrap_count" "count=2"
assert_contains "the first sentence is attributed to its own line" \
  "$two_wrap_out" $'Finding shape: negation\nFinding line: 3'
assert_contains "the second sentence is attributed to its own line" \
  "$two_wrap_out" $'Finding shape: negation\nFinding line: 4'

# Two textually identical sentences must not both pin to the first match.
# `${var%%"$s"*}` always anchors at the earliest occurrence, so a cursor has
# to walk past each already-attributed sentence.
NEG_DUP="$TEST_TMPDIR/negation-duplicate-sentences.md"
cat >"$NEG_DUP" <<'EOF'
# Duplicate-sentence paragraph

Do not use markdown.
Do not use markdown.
EOF
dup_out="$(bash "$DETECT" "$NEG_DUP")"
dup_lines="$(printf '%s\n' "$dup_out" | awk '/^Finding shape: negation$/{getline; if($1=="Finding" && $2=="line:") print $3}')"
assert_contains "identical later sentence keeps its own line" \
  "$(printf '%s' "$dup_lines")" $'3\n4'

# Sibling list items are separate blocks. Joining them would let the second
# item's `Prefer` pair the first item's prohibition.
NEG_LIST_SIBLING="$TEST_TMPDIR/negation-list-siblings.md"
cat >"$NEG_LIST_SIBLING" <<'EOF'
# List-sibling fixture

- Do not use markdown
- Prefer HTML.
EOF
list_sib_out="$(bash "$DETECT" "$NEG_LIST_SIBLING")"
assert_contains "a later list item cannot pair an earlier item" \
  "$list_sib_out" "Finding shape: negation"

# Inline backticks on an earlier line must not shift attribution.
NEG_TICK_ATTR="$TEST_TMPDIR/negation-tick-attr.md"
cat >"$NEG_TICK_ATTR" <<'EOF'
# Tick attribution fixture

Use `foo`.
Do not use markdown.
EOF
tick_attr_out="$(bash "$DETECT" "$NEG_TICK_ATTR")"
assert_contains "attribution ignores earlier inline backticks" \
  "$tick_attr_out" $'Finding shape: negation\nFinding line: 4'

# Line-scoped shapes on a later line must not print before an earlier
# negation once the file is flushed — per-file rows sort by line number.
NEG_ORDER="$TEST_TMPDIR/negation-order.md"
cat >"$NEG_ORDER" <<'EOF'
# Order fixture

Do not use markdown
in the summary. Empirically observed later.
EOF
order_out="$(bash "$DETECT" "$NEG_ORDER")"
# The printed order must be negation (line 3) then citation (line 4).
order_shapes="$(printf '%s\n' "$order_out" | awk '/^Finding shape:/{print $3}')"
assert_contains "findings print in line-number order" \
  "$(printf '%s' "$order_shapes")" $'negation\ncitation'

# The imperative gate is PER SENTENCE. A line-level gate admits the whole line
# on its first sentence and then lets a later DESCRIPTIVE sentence be reported —
# the exact prose the gate exists to exclude, re-entering behind a compliant
# opener.
NEG_SENTGATE="$TEST_TMPDIR/negation-sentence-gate.md"
cat >"$NEG_SENTGATE" <<'EOF'
# Per-sentence fixture

Do not use markdown; instead use HTML. Older versions do not support SVG.
EOF
sentgate_out="$(bash "$DETECT" "$NEG_SENTGATE")"
assert_not_contains "a descriptive later sentence cannot ride an imperative opener" \
  "$sentgate_out" "Finding shape: negation"

# ...but a genuinely imperative later sentence still selects, so the per-sentence
# gate narrows without costing the multi-sentence case.
NEG_TWO="$TEST_TMPDIR/negation-two-imperatives.md"
cat >"$NEG_TWO" <<'EOF'
# Two-imperative fixture

Never commit a secret. Do not use markdown.
EOF
two_out="$(bash "$DETECT" "$NEG_TWO")"
assert_contains "an imperative later sentence still selects" "$two_out" "Finding shape: negation"
assert_contains "and reports its own marker" "$two_out" "Finding marker: do not"

# Ordered-list items use either delimiter, and a task-list checkbox is an
# ordinary way this repo writes a directive. Missing any of these withholds
# silently, which is the direction this rule set exists to avoid.
NEG_MARKERS="$TEST_TMPDIR/negation-markers.md"
cat >"$NEG_MARKERS" <<'EOF'
# Marker fixture

1. Do not use markdown.

2) Never call the tool directly.

- [ ] Avoid restating the rule in the body.

- [x] Do not emit a bare summary.
EOF
markers_out="$(bash "$DETECT" "$NEG_MARKERS")"
markers_count="$(printf '%s\n' "$markers_out" | grep -c '^Finding shape: negation')"
assert_contains "both ordered-list delimiters and both checkbox states reach the cue" \
  "count=$markers_count" "count=4"

# SKILL.md's `Uncommitted .md files:` line previews the same discovery with a grep rather
# than with detect.sh's parse, so it shares the defect CLASS without sharing the code: git
# C-quotes a path it treats specially, and a quoted record ends with the closing quote, not
# `.md`. A bare `grep '\.md$'` therefore dropped every spaced, arrowed, backslashed or
# quoted markdown file from the preview with no signal at all — the same silent false
# negative the parse fix above removes from detect.sh. The grep is EXTRACTED from SKILL.md
# and executed here rather than restated, because a restatement keeps passing while the real
# line rots, which is exactly how the two surfaces drifted apart in the first place.
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
  skill_grep="$(sed -n 's/^Uncommitted \.md files: !`git status --porcelain 2>\/dev\/null | \(grep [^|]*\) | head.*/\1/p' "$SKILL_MD")"
  if [[ -n "$skill_grep" ]]; then
    skill_out="$(cd "$PORC_REPO" && eval "git status --porcelain 2>/dev/null | $skill_grep")"
    # The quoted-path half needs the arrow fixture, which not every filesystem can
    # hold — same hazard the porcelain cases above are gated on, so gate it the same
    # way rather than let it fail for a reason unrelated to the preview.
    if fixture_landed "$PORC_REPO" 'notes -> draft.md'; then
      assert_contains "SKILL.md preview keeps a quoted .md path" "$skill_out" 'notes -> draft.md'
    else
      # discriminating-skip-ok: covers 0.20.1's preview grep, not this change; the
      # ordinary-path assertion below still proves the grep was extracted and ran.
      skip_case "filesystem rejects an arrow in a filename (SKILL.md preview parity)"
    fi
    assert_contains "SKILL.md preview still keeps an ordinary .md path" "$skill_out" 'plain.md'
  else
    fail "SKILL.md preview grep is extractable" "a grep expression" "no match in $SKILL_MD"
  fi
else
  fail "SKILL.md exists for the parity check" "$SKILL_MD" "missing"
fi

# --- Porcelain discovery: octal-escaped paths survive the parse (#3164) ---------------
# v1 porcelain renders a non-ASCII or control byte as a C-style octal escape inside a
# quoted path: the two UTF-8 bytes of the é in `café.md` arrive as the eight characters
# `\303\251`, which no amount of quote-stripping resolves back to a real name. The -z
# form emits those bytes verbatim, so the path reaches the audit.

ESC_REPO="$TEST_TMPDIR/porcelain-escapes-repo"
mkdir -p "$ESC_REPO"
git -C "$ESC_REPO" init -q
git -C "$ESC_REPO" config user.email fixture@example.invalid
git -C "$ESC_REPO" config user.name fixture

nonascii_name='café.md'
printf '# non-ascii\n\nEmpirically observed in the non-ASCII file.\n' >"$ESC_REPO/$nonascii_name"
printf '# spaced\n\nEmpirically observed in the spaced file.\n' >"$ESC_REPO/spaced name.md"

# Both octal-escape fixtures below prove the same thing, and neither is creatable
# everywhere, so track whether AT LEAST ONE ran. If none did, the group has proved
# nothing and must say so loudly rather than tally green.
esc_discriminators=0

esc_out="$(cd "$ESC_REPO" && bash "$DETECT" 2>/dev/null)"
if fixture_landed "$ESC_REPO" "$nonascii_name"; then
  assert_contains "octal-escaped non-ASCII path is discovered" "$esc_out" "$nonascii_name"
  esc_discriminators=$((esc_discriminators + 1))
else
  # discriminating-skip-ok: the control-byte case below proves the same escape
  # class, and the guard after it fails outright if neither fixture landed.
  find "$ESC_REPO" -maxdepth 1 -name '*.md' ! -name 'spaced name.md' -delete 2>/dev/null
  skip_case "filesystem rejects a non-ASCII byte in a filename"
fi
assert_contains "quoted spaced path is still discovered" "$esc_out" "spaced name.md"

# A control byte is escaped the same way (`\t`). Not every filesystem accepts one.
tab_name="$(printf 'tab\there.md')"
printf '# tab\n\nEmpirically observed in the tab file.\n' >"$ESC_REPO/$tab_name" 2>/dev/null || true
if fixture_landed "$ESC_REPO" "$tab_name"; then
  tab_out="$(cd "$ESC_REPO" && bash "$DETECT" 2>/dev/null)"
  assert_contains "octal-escaped control-byte path is discovered" "$tab_out" "$tab_name"
  esc_discriminators=$((esc_discriminators + 1))
else
  # discriminating-skip-ok: the non-ASCII case above proves the same escape
  # class, and the guard below fails outright if neither fixture landed.
  find "$ESC_REPO" -maxdepth 1 -name '*here.md' -delete 2>/dev/null
  skip_case "filesystem rejects a tab in a filename"
fi

if [[ "$esc_discriminators" -eq 0 ]]; then
  fail_discriminating_skip "no octal-escaped fixture landed — #3164's proving coverage did not run"
fi

# A rename whose NEW path is itself octal-escaped: v1 cannot name it, so this
# discriminates the -z read the same way the untracked cases above do.
printf '# origin\n\nEmpirically observed in the origin file.\n' >"$ESC_REPO/origin.md"
git -C "$ESC_REPO" add origin.md
git -C "$ESC_REPO" commit -qm 'seed escaped-rename fixture'
git -C "$ESC_REPO" mv origin.md "$nonascii_name-renamed.md"
if fixture_landed "$ESC_REPO" "$nonascii_name-renamed.md"; then
  esc_rename_out="$(cd "$ESC_REPO" && bash "$DETECT" 2>/dev/null)"
  assert_contains "escaped rename resolves to the new path" "$esc_rename_out" "$nonascii_name-renamed.md"
else
  # discriminating-skip-ok: same escape class as the untracked cases above, which
  # the esc_discriminators guard already covers.
  skip_case "filesystem rejects a non-ASCII byte in a renamed filename"
fi

# Under -z a rename emits the NEW path first and the ORIGINAL as a following record,
# which must be consumed and discarded. The failure mode is NOT that the audit targets
# a path that no longer exists: the leaked record still carries the `XY ` prefix, so
# `${record:3}` chops three characters off the ORIGINAL path. Naming the origin so that
# chopping three characters yields a REAL, CLEAN, COMMITTED file is what makes this
# assertion discriminate at all — the audit then reports findings against a file the
# user never touched and git never listed. Asserting on the bare origin name instead
# would be VACUOUS: `${"origin.md":3}` is `gin.md`, a string the run never emits, so the
# assertion could not fail however the loop behaved. `sort -u` dedupes, so the collided
# name must not itself be a target either.
RENAME_REPO="$TEST_TMPDIR/rename-origin-repo"
mkdir -p "$RENAME_REPO"
git -C "$RENAME_REPO" init -q
git -C "$RENAME_REPO" config user.email fixture@example.invalid
git -C "$RENAME_REPO" config user.name fixture
printf '# secret\n\nEmpirically observed in the secret file.\n' >"$RENAME_REPO/secret.md"
printf '# abc\n\nEmpirically observed in the abc file.\n' >"$RENAME_REPO/abcsecret.md"
git -C "$RENAME_REPO" add secret.md abcsecret.md
git -C "$RENAME_REPO" commit -qm 'seed rename-origin collision fixture'
git -C "$RENAME_REPO" mv abcsecret.md moved.md
rename_origin_out="$(cd "$RENAME_REPO" && bash "$DETECT" 2>/dev/null)"
assert_contains "rename resolves to the new path" "$rename_origin_out" "Summary file: moved.md"
assert_not_contains "rename origin is consumed, not sliced into a clean committed file" "$rename_origin_out" "Summary file: secret.md"

# A newline in a filename is a control byte the -z read recovers intact. If
# sort/dedup then serializes TARGETS with newline delimiters, mapfile splits
# the name into two nonexistent targets and the file drops out again.
NL_REPO="$TEST_TMPDIR/newline-name-repo"
mkdir -p "$NL_REPO"
git -C "$NL_REPO" init -q
git -C "$NL_REPO" config user.email fixture@example.invalid
git -C "$NL_REPO" config user.name fixture
nl_name="$(printf 'new\nline.md')"
printf '# newline\n\nEmpirically observed in the newline file.\n' >"$NL_REPO/$nl_name" 2>/dev/null || true
if fixture_landed "$NL_REPO" "$nl_name"; then
  nl_out="$(cd "$NL_REPO" && bash "$DETECT" 2>/dev/null)"
  assert_contains "newline-bearing path survives sort/dedup" "$nl_out" "Empirically observed in the newline file"
else
  # discriminating-skip-ok: the tab and non-ASCII cases already prove the
  # escape class; this pins the post-parse sort, which not every filesystem
  # can hold a name for.
  skip_case "filesystem rejects a newline in a filename"
fi

# --- Recall paraphrases (false-negative regression, #3129) ---------------------------
# These forms are in the shape table's semantic definition and were silent
# under the old literal tripwires. Narrowing the matchers back to
# `## Why this file exists` / `was renamed to` / `- /slug —` only must fail
# this block.

RECALL="$SCRIPT_DIR/../evals/fixtures/recall-paraphrases.md"
recall_out="$(bash "$DETECT" "$RECALL" 2>/dev/null)"
assert_contains "off-level why-this-file-exists is preamble" "$recall_out" "Finding shape: preamble"
assert_contains "Motivation heading is preamble" "$recall_out" "Motivation"
assert_contains "Renamed from is citation" "$recall_out" "Finding shape: citation"
assert_contains "Renamed from excerpt" "$recall_out" "Renamed from foo to bar"
assert_contains "table slash-command is enum-list" "$recall_out" "Finding shape: enum-list"
assert_contains "table /net-audit excerpt" "$recall_out" "/net-audit"
assert_contains "bold roster is enum-list" "$recall_out" "Agent config"
assert_not_contains "recall fixture is not a no-targets run" "$recall_out" "status: no-targets"

# Isolated lines so each assertion can fail independently of the others.
PREAMBLE_H3="$TEST_TMPDIR/preamble-h3.md"
printf '%s\n' '### Why this file exists' >"$PREAMBLE_H3"
preamble_h3_out="$(bash "$DETECT" "$PREAMBLE_H3")"
assert_contains "H3 why-this-file-exists flags" "$preamble_h3_out" "Finding shape: preamble"

MOTIVATION="$TEST_TMPDIR/motivation.md"
printf '%s\n' '## Motivation' >"$MOTIVATION"
motivation_out="$(bash "$DETECT" "$MOTIVATION")"
assert_contains "Motivation heading flags" "$motivation_out" "Finding shape: preamble"

RENAMED="$TEST_TMPDIR/renamed.md"
printf '%s\n' 'Renamed from foo to bar.' >"$RENAMED"
renamed_out="$(bash "$DETECT" "$RENAMED")"
assert_contains "Renamed from flags as citation" "$renamed_out" "Finding shape: citation"

TABLE="$TEST_TMPDIR/table.md"
# shellcheck disable=SC2016  # literal backticks belong in the fixture text
printf '%s\n' '| Consumer | Role |' '|---|---|' '| `/net-audit` | scans |' >"$TABLE"
table_out="$(bash "$DETECT" "$TABLE")"
assert_contains "table consumer row flags as enum-list" "$table_out" "Finding shape: enum-list"
assert_not_contains "table separator is not a finding excerpt" "$table_out" "Finding excerpt: |---|"

PLUGINS_NOUN="$TEST_TMPDIR/plugins-noun.md"
printf '%s\n' 'The following three plugins consume this rule.' >"$PLUGINS_NOUN"
plugins_out="$(bash "$DETECT" "$PLUGINS_NOUN")"
assert_contains "following N plugins is enum-list" "$plugins_out" "Finding shape: enum-list"

BOLD_ROSTER="$TEST_TMPDIR/bold-roster.md"
printf '%s\n' '- **Agent config** — personal overlay' >"$BOLD_ROSTER"
bold_out="$(bash "$DETECT" "$BOLD_ROSTER")"
assert_contains "bold roster flags as enum-list" "$bold_out" "Finding shape: enum-list"

# Empty / missing target is stdout-visible even with stderr discarded.
missing_out="$(bash "$DETECT" "$TEST_TMPDIR/does-not-exist.md" 2>/dev/null)"
assert_contains "missing file prints status: no-targets on stdout" "$missing_out" "status: no-targets"
EMPTY_DIR="$TEST_TMPDIR/empty-dir"
mkdir -p "$EMPTY_DIR"
empty_dir_out="$(bash "$DETECT" "$EMPTY_DIR" 2>/dev/null)"
assert_contains "empty dir prints status: no-targets on stdout" "$empty_dir_out" "status: no-targets"
assert_not_contains "clean scanned file is not no-targets" "$clean_out" "status: no-targets"

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed (%d skipped).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed (%d skipped).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
