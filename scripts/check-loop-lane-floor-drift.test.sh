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
# registration pointing at nothing, and the two ways the extractor could go
# blind and pass everything forever.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2

SUT="$SCRIPT_DIR/check-loop-lane-floor-drift.sh"
if [[ ! -r "$SUT" ]]; then
  fail "system under test not readable: $SUT"
  test_harness::report
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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

run() {
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

test_harness::report
