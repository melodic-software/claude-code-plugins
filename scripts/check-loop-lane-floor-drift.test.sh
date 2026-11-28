#!/usr/bin/env bash
# test-scope: plugins/*/reference/reader-contract.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh" || exit 2

SUT="$SCRIPT_DIR/check-loop-lane-floor-drift.sh"
if [[ ! -r "$SUT" ]]; then
  fail "system under test not readable: $SUT"
  test_harness::report
  exit 1
fi

TMP=""
fixture_tree::build TMP --git --label loop-lane-floor-drift || {
  fail "could not build the fixture repository"
  test_harness::report
  exit 1
}

SOURCE_REL="plugins/rate-limits/reference/reader-contract.md"
EXACT_CONSUMERS=(
  "plugins/work-items/skills/work-loop/SKILL.md"
  "plugins/work-items/skills/attend-queue/SKILL.md"
  "plugins/source-control/skills/babysit-loop/SKILL.md"
  "plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md"
  "plugins/source-control/skills/pull-request/reference/watch-handoff.md"
)
VALUES_CONSUMERS=(
  "prompts/loops/loop-lane-prompts.md"
)

mapfile -t DATA_CARRIER_PATHS < <(awk '
  /^DATA_CARRIERS=\(/ { f = 1; next }
  f && /^\)/ { exit }
  f { sub(/^[[:blank:]]*"/, ""); sub(/ .*/, ""); if ($0 != "") print }
' "$SUT")
((${#DATA_CARRIER_PATHS[@]})) || fail "no DATA_CARRIERS entry read from $SUT"

floor_block() {
  cat <<'EOF'
- **Snapshot file (fixed path):** `~/.claude/rate-limits/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`
- **Staleness rule:** a snapshot older than **10 minutes** is stale. Treat the
  windows as **unknown**.
- **Drain-then-pause:** on a trip, finish in-flight work and pause.
- **Account switch:** while paused, **MUST** read `.oauthAccount.emailAddress` from `~/.claude.json`; a changed account below 90 drops the latch.
EOF
}

floor_block_quoted() {
  cat <<'EOF'
> - **Snapshot file (fixed path):**
>   `~/.claude/rate-limits/rate-limits.json`
> - **Pause threshold (fixed):** pause when **either** window
>   reports `used_percentage >= 90`
> - **Pause end:** the **tripped** window's `resets_at`
> - **Staleness rule:** a snapshot older than **10 minutes** is
>   stale. Treat the windows as **unknown**.
> - **Drain-then-pause:** on a trip, finish in-flight work and
>   pause.
> - **Account switch:** while paused, **MUST** read
>   `.oauthAccount.emailAddress` from `~/.claude.json`; a changed
>   account below 90 drops the latch.
EOF
}

no_floor() {
  printf 'This lane no longer inlines anything.\n'
}

data_carrier_block() {
  printf 'Fixture data, not an operable copy of the floor.\n\n'
  floor_block | sed 's/>= 90/>= 42/'
}

self_exempting_consumer() {
  printf 'loop-lane-floor-carrier%s illustrative example, not an operable copy\n\n' '-ok:'
  floor_block
  printf '\nThis lane applies the floor above on every cycle.\n'
}

write_file() {
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
  for c in "${DATA_CARRIER_PATHS[@]}"; do write_file "$c" data_carrier_block; done
}

run() {
  git_test_config "$TMP" add -A || {
    fail "could not stage the fixture tree"
    return 2
  }
  LOOP_LANE_FLOOR_ROOT="$TMP" bash "$SUT" "$@" 2>&1
}

mutate() {
  local file="$1" prog="$2"
  sed "$prog" "$file" >"$file.mutated" && mv "$file.mutated" "$file"
}

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)) && grep -q '6 consumer(s) match' <<<"$out"; then
  ok "a conforming tree passes and names how many consumers it compared"
else
  fail "conforming tree should pass (rc=$rc): $out"
fi

out="$(run)"
rc=$?
if ((rc == 0)); then
  ok "bare invocation behaves as --check"
else
  fail "bare invocation should pass on a conforming tree (rc=$rc): $out"
fi

out="$(run --list)"
rc=$?
if ((rc == 0)) && grep -q '1 source, 6 registered consumer(s)' <<<"$out" &&
  grep -q 'consumer values prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "--list reports the source and every registered consumer with its mode"
else
  fail "--list should enumerate the registry (rc=$rc): $out"
fi

out="$(run --whatever)"
rc=$?
if ((rc == 2)) && grep -q 'usage:' <<<"$out"; then
  ok "an unknown argument exits 2 with usage"
else
  fail "unknown argument should exit 2 (rc=$rc): $out"
fi

seed_tree
mutate "$TMP/plugins/work-items/skills/work-loop/SKILL.md" 's/is stale\. Treat the/is stale, treat the/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (exact): plugins/work-items/skills/work-loop/SKILL.md' <<<"$out"; then
  ok "a punctuation-only change in one lane body fails as exact drift"
else
  fail "exact drift should fail (rc=$rc): $out"
fi

if grep -q 'is stale, treat the' <<<"$out"; then
  ok "the exact-drift report shows the drifted line"
else
  fail "exact-drift report should diff the block: $out"
fi

seed_tree
mutate "$TMP/$SOURCE_REL" 's/\*\*10 minutes\*\*/**15 minutes**/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q '6 drifted or unresolvable consumer(s)' <<<"$out"; then
  ok "a value changed only in the source fails all six consumers"
else
  fail "source-side change should fail every consumer (rc=$rc): $out"
fi

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)); then
  ok "a blockquoted, re-wrapped copy passes in values mode"
else
  fail "re-wrapped values consumer should pass (rc=$rc): $out"
fi

mutate "$TMP/prompts/loops/loop-lane-prompts.md" 's/>= 90/>= 80/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (values): prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "a changed value in a values-mode consumer fails despite free wrapping"
else
  fail "values-mode value change should fail (rc=$rc): $out"
fi

seed_tree
write_file "plugins/source-control/skills/babysit-loop/SKILL.md" no_floor
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'MISSING FLOOR: plugins/source-control/skills/babysit-loop/SKILL.md' <<<"$out"; then
  ok "a consumer that dropped the inlined floor fails rather than passing vacuously"
else
  fail "dropped floor should fail (rc=$rc): $out"
fi

seed_tree
rm "$TMP/prompts/loops/loop-lane-prompts.md"
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'STALE REGISTRATION: prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "a registration matching no file fails instead of being skipped"
else
  fail "stale registration should fail (rc=$rc): $out"
fi

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

seed_tree
mutate "$TMP/$SOURCE_REL" 's/- \*\*Snapshot file (fixed path):\*\*/- **Snapshot file path:**/'
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q 'opens the floor block 0 time(s)' <<<"$out"; then
  ok "a source the marker no longer matches exits 2 rather than passing"
else
  fail "unmatched source marker should exit 2 (rc=$rc): $out"
fi

seed_tree
mutate "$TMP/$SOURCE_REL" '/\*\*Drain-then-pause:\*\*/d'
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q "missing the '\*\*Drain-then-pause:\*\*' bullet" <<<"$out"; then
  ok "a source block missing a floor bullet exits 2 rather than comparing"
else
  fail "incomplete source block should exit 2 (rc=$rc): $out"
fi

seed_tree
rm "$TMP/$SOURCE_REL"
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q 'source not readable' <<<"$out"; then
  ok "an unreadable source exits 2"
else
  fail "missing source should exit 2 (rc=$rc): $out"
fi

seed_tree
write_file "plugins/some-new-plugin/skills/new-lane/SKILL.md" floor_block
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: plugins/some-new-plugin/skills/new-lane/SKILL.md' <<<"$out"; then
  ok "a new file carrying the floor fails until it is registered"
else
  fail "unregistered copy should fail (rc=$rc): $out"
fi

if grep -q 'DRIFT' <<<"$out"; then
  fail "the unregistered copy matches the source, so no DRIFT should be reported: $out"
else
  ok "an unregistered copy fails for being unregistered, not for drifting"
fi

seed_tree
write_file "prompts/loops/some-new-template.md" floor_block_quoted
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: prompts/loops/some-new-template.md' <<<"$out"; then
  ok "a blockquoted unregistered copy is discovered"
else
  fail "blockquoted unregistered copy should fail (rc=$rc): $out"
fi

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)) && ! grep -q 'UNREGISTERED' <<<"$out"; then
  ok "the owning contract is not reported as an unregistered copy"
else
  fail "clean tree should stay clean (rc=$rc): $out"
fi

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

seed_tree
out="$(run --list)"
rc=$?
if ((rc == 0)) && grep -q '^carrier .*plugins/work-items/skills/work-loop/SKILL.md' <<<"$out"; then
  ok "--list reports what the repo-wide scan found"
else
  fail "--list should report discovered carriers (rc=$rc): $out"
fi

seed_tree
out="$(run --check)"
rc=$?
if ((rc == 0)) && grep -q 'NOT COMPARED (data carrier): scripts/check-loop-lane-floor-drift.test.sh' <<<"$out"; then
  ok "--check names every data carrier it excused on the passing path"
else
  fail "--check should report the exception set (rc=$rc): $out"
fi

seed_tree
write_file "plugins/some-new-plugin/skills/new-lane/SKILL.md" self_exempting_consumer
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: plugins/some-new-plugin/skills/new-lane/SKILL.md' <<<"$out"; then
  ok "a file naming the old exemption token cannot excuse its own floor copy"
else
  fail "self-exemption must be impossible (rc=$rc): $out"
fi

mutate "$TMP/plugins/some-new-plugin/skills/new-lane/SKILL.md" 's/>= 90/>= 80/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'UNREGISTERED COPY: plugins/some-new-plugin/skills/new-lane/SKILL.md' <<<"$out"; then
  ok "a self-exempting copy that has drifted still fails"
else
  fail "drifted self-exempting copy must fail (rc=$rc): $out"
fi

seed_tree
git_test_config "$TMP" add -A >/dev/null
git_test_config "$TMP" rm -q --cached "$SOURCE_REL" >/dev/null
out="$(LOOP_LANE_FLOOR_ROOT="$TMP" bash "$SUT" --check 2>&1)"
rc=$?
if ((rc == 2)) && grep -q 'the scan is not working' <<<"$out"; then
  ok "a discovery pass that cannot see the source exits 2, never a clean run"
else
  fail "discovery self-proof should exit 2 (rc=$rc): $out"
fi

seed_tree
mutate "$TMP/plugins/source-control/skills/babysit-loop/SKILL.md" 's/\*\*MUST\*\*/**may**/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (exact): plugins/source-control/skills/babysit-loop/SKILL.md' <<<"$out" &&
  grep -q '1 drifted or unresolvable consumer(s)' <<<"$out"; then
  ok "a weakened Account switch bullet in one lane body fails as exact drift"
else
  fail "Account switch drift should fail exactly one consumer (rc=$rc): $out"
fi

seed_tree
mutate "$TMP/prompts/loops/loop-lane-prompts.md" 's/below 90 drops/below 80 drops/'
out="$(run --check)"
rc=$?
if ((rc == 1)) && grep -q 'DRIFT (values): prompts/loops/loop-lane-prompts.md' <<<"$out"; then
  ok "a changed Account switch value in a values-mode consumer fails"
else
  fail "Account switch values drift should fail (rc=$rc): $out"
fi

seed_tree
mutate "$TMP/$SOURCE_REL" '/\*\*Account switch:\*\*/d'
out="$(run --check)"
rc=$?
if ((rc == 2)) && grep -q "missing the '\*\*Account switch:\*\*' bullet" <<<"$out"; then
  ok "a source block missing the Account switch bullet exits 2 rather than comparing"
else
  fail "source without the Account switch bullet should exit 2 (rc=$rc): $out"
fi

test_harness::report
