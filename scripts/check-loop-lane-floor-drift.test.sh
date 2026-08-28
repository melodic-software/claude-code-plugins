#!/usr/bin/env bash
# Black-box contract test for check-loop-lane-floor-drift.sh.
#
# Self-contained and cwd-independent: builds a throwaway root holding a fake
# reader contract and fake consumers at the registered paths, points the SUT at
# it with LOOP_LANE_FLOOR_ROOT, and asserts on exit code plus output. Mutates
# only its own mktemp dir.
#
# The cases that earn their keep are the ones proving the gate goes RED. A
# drift check nobody has watched fail is the false-green shape
# docs/conventions/liveness-assertion/ names, and this gate's whole reason for
# existing is that the prose claim it replaces ("fleet audits check conformance
# per consumer") was exactly that. So every failure class gets a case: exact
# drift, values drift, a consumer that stopped inlining the floor, a
# registration pointing at nothing, a COPY NOBODY REGISTERED, and the two ways
# the extractor could go blind and pass everything forever.
#
# The fixture root is a throwaway git repository, because the SUT enumerates
# the corpus with git the way every sibling gate in scripts/ does. It is built
# through scripts/test-git-helpers.sh, which clears the ambient git environment
# so a fixture's identity can never land in the caller's checkout (#2840).
#
# loop-lane-floor-carrier-ok: the fixture heredocs below open with the floor's
# marker line as stand-in test data, so the SUT's repo-wide scan sees this file
# as a carrier. It is a test fixture, not a consumer copy: nothing here ships,
# and the values are deliberately abridged so a real floor change must not
# touch this file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh" || exit 2

SUT="$SCRIPT_DIR/check-loop-lane-floor-drift.sh"
if [[ ! -r "$SUT" ]]; then
  fail "system under test not readable: $SUT"
  test_harness::report
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git_init_test_repo "$TMP" || {
  fail "could not initialize the fixture repository"
  test_harness::report
  exit 1
}

SOURCE_REL="plugins/rate-limit-guard/reference/reader-contract.md"
EXACT_CONSUMERS=(
  "plugins/work-items/skills/work-loop/SKILL.md"
  "plugins/work-items/skills/attend-queue/SKILL.md"
  "plugins/source-control/skills/babysit-loop/SKILL.md"
  "plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md"
)
VALUES_CONSUMERS=(
  "prompts/loops/loop-lane-prompts.md"
  "prompts/loops/loop-lane-profile-claude-code-plugins.md"
)

# The floor block as the fixtures carry it. Short stand-ins for the real
# bullets: this suite tests the gate's comparison, not the guard's values.
floor_block() {
  cat <<'EOF'
- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`
- **Staleness rule:** a snapshot older than **10 minutes** is stale. Treat the
  windows as **unknown**.
- **Drain-then-pause:** on a trip, finish in-flight work and pause.
EOF
}

# Same values, re-wrapped inside a blockquote — what the launch-prompt
# templates legitimately do, and what `values` mode exists to tolerate.
floor_block_quoted() {
  cat <<'EOF'
> - **Tee file (fixed path):**
>   `~/.claude/rate-limit-guard/rate-limits.json`
> - **Pause threshold (fixed):** pause when **either** window
>   reports `used_percentage >= 90`
> - **Pause end:** the **tripped** window's `resets_at`
> - **Staleness rule:** a snapshot older than **10 minutes** is
>   stale. Treat the windows as **unknown**.
> - **Drain-then-pause:** on a trip, finish in-flight work and
>   pause.
EOF
}

# A consumer body that no longer carries the floor at all.
no_floor() {
  printf 'This lane no longer inlines anything.\n'
}

# A file holding the marker as DATA, declaring so inline. The token is printed
# in two halves so that grepping this suite for the annotation finds the one at
# the top of the file, which is this suite's own declaration, rather than a
# fixture string that belongs to a single case.
annotated_carrier() {
  printf 'loop-lane-floor-carrier%s a fixture, not a consumer copy\n\n' '-ok:'
  floor_block
}

write_file() {
  # write_file <relative path> <body-producing function>
  local rel="$1" body="$2"
  mkdir -p "$TMP/$(dirname "$rel")"
  {
    printf '# Fixture\n\nPreamble prose above the block.\n\n'
    "$body"
    printf '\nTrailing prose below the block.\n'
  } >"$TMP/$rel"
}

seed_tree() {
  rm -rf "${TMP:?}"/*
  write_file "$SOURCE_REL" floor_block
  local c
  for c in "${EXACT_CONSUMERS[@]}"; do write_file "$c" floor_block; done
  for c in "${VALUES_CONSUMERS[@]}"; do write_file "$c" floor_block_quoted; done
}

# The SUT enumerates tracked files, so every case stages the fixture tree
# before invoking it. Staging inside run() rather than at the end of seed_tree
# is deliberate: a case that adds or deletes a file after seeding then needs no
# second call, and no case can forget one.
run() {
  git_test_config "$TMP" add -A || {
    fail "could not stage the fixture tree"
    return 2
  }
  LOOP_LANE_FLOOR_ROOT="$TMP" bash "$SUT" "$@" 2>&1
}

# mutate <file> <sed program> — the drift each case introduces.
# Not `sed -i`: that spelling is GNU-only (BSD sed reads the next argument as a
# backup suffix), and scripts/check-shell-portability.sh rejects it.
mutate() {
  local file="$1" prog="$2"
  sed "$prog" "$file" >"$file.mutated" && mv "$file.mutated" "$file"
}

# --- 1. A conforming tree passes -------------------------------------------

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)) && grep -q '6 consumer(s) match' <<<"$out"; then
  ok "a conforming tree passes and names how many consumers it compared"
else
  fail "conforming tree should pass (rc=$rc): $out"
fi

# --- 2. Bare invocation is --check -----------------------------------------

out="$(run)"
rc=$?
if ((rc == 0)); then
  ok "bare invocation behaves as --check"
else
  fail "bare invocation should pass on a conforming tree (rc=$rc): $out"
fi

# --- 3. --list reports the registry without comparing ----------------------

out="$(run --list)"
rc=$?
if ((rc == 0)) && grep -q '1 source, 6 registered consumer(s)' <<<"$out" &&
  grep -q 'consumer values prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "--list reports the source and every registered consumer with its mode"
else
  fail "--list should enumerate the registry (rc=$rc): $out"
fi

# --- 4. An unknown argument is usage, not a silent pass ---------------------

out="$(run --whatever)"
rc=$?
if ((rc == 2)) && grep -q 'usage:' <<<"$out"; then
  ok "an unknown argument exits 2 with usage"
else
  fail "unknown argument should exit 2 (rc=$rc): $out"
fi

# --- 5. Exact drift in one lane body fails ---------------------------------
# This is the historical defect: two de-slop shards rewrote punctuation inside
# the staleness bullet of the lane bodies and left the source untouched.

seed_tree
mutate "$TMP/plugins/work-items/skills/work-loop/SKILL.md" 's/is stale\. Treat the/is stale, treat the/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (exact): plugins/work-items/skills/work-loop/SKILL.md' <<<"$out"; then
  ok "a punctuation-only change in one lane body fails as exact drift"
else
  fail "exact drift should fail (rc=$rc): $out"
fi

# --- 6. The failure names the drifted line ---------------------------------

if grep -q 'is stale, treat the' <<<"$out"; then
  ok "the exact-drift report shows the drifted line"
else
  fail "exact-drift report should diff the block: $out"
fi

# --- 7. A source-side change fails every consumer ---------------------------
# The direction that matters most: changing the OWNER without the copies is the
# same defect seen from the other end.

seed_tree
mutate "$TMP/$SOURCE_REL" 's/\*\*10 minutes\*\*/**15 minutes**/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q '6 drifted or unresolvable consumer(s)' <<<"$out"; then
  ok "a value changed only in the source fails all six consumers"
else
  fail "source-side change should fail every consumer (rc=$rc): $out"
fi

# --- 8. Re-wrapping a `values` consumer is tolerated -----------------------

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)); then
  ok "a blockquoted, re-wrapped copy passes in values mode"
else
  fail "re-wrapped values consumer should pass (rc=$rc): $out"
fi

# --- 9. A changed VALUE in a `values` consumer still fails ------------------
# Values mode forgives wrapping, never a value. Without this the two prompt
# templates would be registered and unchecked.

mutate "$TMP/prompts/loops/loop-lane-prompts.md" 's/>= 90/>= 80/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (values): prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "a changed value in a values-mode consumer fails despite free wrapping"
else
  fail "values-mode value change should fail (rc=$rc): $out"
fi

# --- 10. A consumer that stopped inlining the floor fails ------------------
# Deleting the block must not read as "nothing to compare, therefore clean".

seed_tree
write_file "plugins/source-control/skills/babysit-loop/SKILL.md" no_floor
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'MISSING FLOOR: plugins/source-control/skills/babysit-loop/SKILL.md' <<<"$out"; then
  ok "a consumer that dropped the inlined floor fails rather than passing vacuously"
else
  fail "dropped floor should fail (rc=$rc): $out"
fi

# --- 11. A registration pointing at no file fails --------------------------

seed_tree
rm "$TMP/prompts/loops/loop-lane-profile-claude-code-plugins.md"
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'STALE REGISTRATION: prompts/loops/loop-lane-profile-claude-code-plugins.md' <<<"$out"; then
  ok "a registration matching no file fails instead of being skipped"
else
  fail "stale registration should fail (rc=$rc): $out"
fi

# --- 12. Two floor blocks in one consumer is ambiguous, not a first-hit win -

seed_tree
{
  printf '\n'
  floor_block | sed 's/10 minutes/99 minutes/'
} >>"$TMP/plugins/work-items/skills/attend-queue/SKILL.md"
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'AMBIGUOUS FLOOR: plugins/work-items/skills/attend-queue/SKILL.md' <<<"$out"; then
  ok "a second floor block in one consumer fails as ambiguous"
else
  fail "duplicate block should fail as ambiguous (rc=$rc): $out"
fi

# --- 13. A source whose marker no longer matches is inconclusive -----------
# The blindness case. If the extractor stopped finding the block, every
# comparison would be empty-against-empty and the gate would pass forever.

seed_tree
mutate "$TMP/$SOURCE_REL" 's/- \*\*Tee file (fixed path):\*\*/- **Tee file path:**/'
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q 'opens the floor block 0 time(s)' <<<"$out"; then
  ok "a source the marker no longer matches exits 2 rather than passing"
else
  fail "unmatched source marker should exit 2 (rc=$rc): $out"
fi

# --- 14. A source block missing a floor bullet is inconclusive -------------
# The other blindness case: the marker still matches but the block the gate
# extracted is not the floor, so it refuses to certify anything against it.

seed_tree
mutate "$TMP/$SOURCE_REL" '/\*\*Drain-then-pause:\*\*/d'
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q "missing the '\*\*Drain-then-pause:\*\*' bullet" <<<"$out"; then
  ok "a source block missing a floor bullet exits 2 rather than comparing"
else
  fail "incomplete source block should exit 2 (rc=$rc): $out"
fi

# --- 15. An unreadable source is exit 2, never a clean run -----------------

seed_tree
rm "$TMP/$SOURCE_REL"
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q 'source not readable' <<<"$out"; then
  ok "an unreadable source exits 2"
else
  fail "missing source should exit 2 (rc=$rc): $out"
fi

# --- 16. Every registered path exists in the live repository ---------------
# The registry is hand-maintained, so the live tree is where a rename shows up.
# This is the same stale-guard idiom the sibling list-backed gates use, run
# against the real repo rather than a fixture.

live="$(bash "$SUT" --list 2>&1)"
rc=$?
missing=()
while read -r kind _mode path; do
  [[ "$kind" == consumer ]] || continue
  [[ -r "$SCRIPT_DIR/../$path" ]] || missing+=("$path")
done <<<"$live"
if ((rc == 0)) && ((${#missing[@]} == 0)); then
  ok "every registered consumer exists in this checkout"
else
  fail "registered consumer(s) missing from the checkout: ${missing[*]-} (rc=$rc)"
fi

# --- 17. An unregistered file carrying the floor fails ---------------------
# The registry alone only ever looks where it is told, so a seventh consumer
# would inline the floor, pass CI, and go stale at the next contract change.
# That is the class that produced the original drift: the general copy-drift
# gate could not see these files either.

seed_tree
write_file "plugins/some-new-plugin/skills/new-lane/SKILL.md" floor_block
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: plugins/some-new-plugin/skills/new-lane/SKILL.md' <<<"$out"; then
  ok "a new file carrying the floor fails until it is registered"
else
  fail "unregistered copy should fail (rc=$rc): $out"
fi

# --- 18. It fails even when the unregistered copy matches perfectly --------
# The failure is about being unwatched, not about being wrong today. A copy
# that matches now is exactly the one that silently goes stale later, so a
# byte-perfect unregistered copy must still be reported.

if grep -q 'DRIFT' <<<"$out"; then
  fail "the unregistered copy matches the source, so no DRIFT should be reported: $out"
else
  ok "an unregistered copy fails for being unregistered, not for drifting"
fi

# --- 19. A blockquoted unregistered copy is discovered too -----------------
# Discovery uses the same anchored marker the comparison does, or the
# launch-prompt shape would be a hole in the scan.

seed_tree
write_file "prompts/loops/some-new-template.md" floor_block_quoted
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: prompts/loops/some-new-template.md' <<<"$out"; then
  ok "a blockquoted unregistered copy is discovered"
else
  fail "blockquoted unregistered copy should fail (rc=$rc): $out"
fi

# --- 20. The owning contract is never reported as an unregistered copy -----

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)) && ! grep -q 'UNREGISTERED' <<<"$out"; then
  ok "the owning contract is not reported as an unregistered copy"
else
  fail "clean tree should stay clean (rc=$rc): $out"
fi

# --- 21. An untracked copy is not a CI failure -----------------------------
# Discovery enumerates TRACKED files, the corpus every sibling gate reads. A
# scratch file in someone's working tree ships to nobody and must not turn the
# gate red; the moment it is staged, case 17 applies.

seed_tree
git_test_config "$TMP" add -A >/dev/null
write_file "plugins/scratch/notes.md" floor_block
out="$(LOOP_LANE_FLOOR_ROOT="$TMP" bash "$SUT" --check 2>&1)"
rc=$?
if ((rc == 0)); then
  ok "an untracked copy does not fail the gate"
else
  fail "untracked copy should not fail (rc=$rc): $out"
fi

# --- 22. --list reports the discovered carriers ----------------------------

seed_tree
out="$(run --list)"
rc=$?
if ((rc == 0)) && grep -q '^carrier .*plugins/work-items/skills/work-loop/SKILL.md' <<<"$out"; then
  ok "--list reports what the repo-wide scan found"
else
  fail "--list should report discovered carriers (rc=$rc): $out"
fi

# --- 23. An annotated data carrier is exempt -------------------------------
# A file can hold the marker as data rather than as a consumer copy. This
# suite is the first such file. The annotation is what makes that a decision
# on the record instead of a hardcoded path filter.

seed_tree
write_file "plugins/some-plugin/fixtures/sample.md" annotated_carrier
out="$(run --check)"
rc=$?
if ((rc == 0)); then
  ok "a carrier annotated with a reason is exempt from the registry"
else
  fail "annotated data carrier should pass (rc=$rc): $out"
fi

# --- 24. A bare annotation is not an exemption -----------------------------

mutate "$TMP/plugins/some-plugin/fixtures/sample.md" 's/-ok: a fixture, not a consumer copy/-ok:/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'BARE EXEMPTION: plugins/some-plugin/fixtures/sample.md' <<<"$out"; then
  ok "an annotation with no reason fails instead of exempting"
else
  fail "bare exemption should fail (rc=$rc): $out"
fi

# --- 25. An exemption on a registered consumer is stale --------------------
# Same stale-guard rule the sibling gates use: an exemption must not outlive
# what it excuses, and a registered path is compared regardless.

seed_tree
printf '\nloop-lane-floor-carrier%s no longer true\n' '-ok:' \
  >>"$TMP/plugins/work-items/skills/work-loop/SKILL.md"
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'STALE EXEMPTION: plugins/work-items/skills/work-loop/SKILL.md' <<<"$out"; then
  ok "an exemption on a registered consumer fails as stale"
else
  fail "stale exemption should fail (rc=$rc): $out"
fi

# --- 26. The live repository carries no unregistered copy ------------------
# Runs the scan against the real tree, which is where a new copy actually
# appears. Case 17 proves the mechanism; this proves today's corpus is closed.

live="$(bash "$SUT" --check 2>&1)"
rc=$?
if ((rc == 0)) && ! grep -q 'UNREGISTERED' <<<"$live"; then
  ok "no unregistered copy of the floor exists in this checkout"
else
  fail "live repository carries an unregistered floor copy (rc=$rc): $live"
fi

test_harness::report
