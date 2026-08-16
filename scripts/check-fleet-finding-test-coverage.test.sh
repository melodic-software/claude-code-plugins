#!/usr/bin/env bash
# Self-test for check-fleet-finding-test-coverage.sh. Synthetic trees prove the
# detector catches an emitted finding kind with no test reference, and that a
# stale baseline entry red-lines once coverage lands.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-fleet-finding-test-coverage.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

mk_tree() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/plugins/repo-fleet-hygiene/skills/audit/scripts" "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-fleet-finding-test-coverage.sh"
  printf '%s' "${1:-}" >"$dir/scripts/fleet-finding-test-coverage-baseline.txt"
  printf '%s' "$dir"
}

# Pad emit_finding lists so the extraction floor (>=20) is honest without copying
# the real collector. Kind tokens must match [a-z-]+ (no digits), same as production.
PAD_KINDS=(
  pad-alpha pad-bravo pad-charlie pad-delta pad-echo pad-foxtrot pad-golf pad-hotel
  pad-india pad-juliet pad-kilo pad-lima pad-mike pad-november pad-oscar pad-papa
  pad-quebec pad-romeo pad-sierra pad-tango
)

pad_kinds() {
  local kind
  for kind in "${PAD_KINDS[@]}"; do
    printf 'emit_finding HIGH %s path evidence handoff remedy\n' "$kind"
  done
}

write_collector() {
  local repo="$1"
  shift
  {
    pad_kinds
    for kind in "$@"; do
      printf 'emit_finding MEDIUM %s path evidence handoff remedy\n' "$kind"
    done
  } >"$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh"
}

write_suite() {
  local repo="$1"
  shift
  {
    printf '# synthetic suite\n'
    local kind
    # Pad kinds are always "covered" so scenarios only assert the interesting kinds.
    for kind in "${PAD_KINDS[@]}"; do
      printf 'assert_contains "x" "Finding: %s"\n' "$kind"
    done
    for kind in "$@"; do
      printf 'assert_contains "x" "Finding: %s"\n' "$kind"
    done
  } >"$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh"
}

run_check() {
  local repo="$1"
  (cd "$repo" && bash scripts/check-fleet-finding-test-coverage.sh --check)
}

# Covered kinds pass with an empty baseline.
repo="$(mk_tree)"
write_collector "$repo" covered-one covered-two
write_suite "$repo" covered-one covered-two
if run_check "$repo" >/dev/null; then ok "fully covered kinds pass --check"; else fail "fully covered kinds wrongly flagged"; fi
rm -rf "$repo"

# An uncovered kind with no baseline entry fails.
repo="$(mk_tree)"
write_collector "$repo" covered-one uncovered-kind
write_suite "$repo" covered-one
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNCOVERED FINDING KIND: uncovered-kind"* ]]; then
  ok "uncovered kind without baseline red-lines"
else
  fail "uncovered kind not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# A baselined uncovered kind passes; removing coverage debt without clearing the
# baseline is a stale entry.
repo="$(mk_tree $'uncovered-kind\n')"
write_collector "$repo" covered-one uncovered-kind
write_suite "$repo" covered-one
if run_check "$repo" >/dev/null; then ok "baselined uncovered kind passes --check"; else fail "baselined uncovered kind wrongly flagged"; fi
write_suite "$repo" covered-one uncovered-kind
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"STALE BASELINE ENTRY: uncovered-kind"* ]]; then
  ok "stale baseline entry red-lines once coverage lands"
else
  fail "stale baseline not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# A baseline entry for a kind the collector no longer emits is stale.
repo="$(mk_tree $'retired-kind\n')"
write_collector "$repo" covered-one
write_suite "$repo" covered-one
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"STALE BASELINE ENTRY: retired-kind"* ]]; then
  ok "baseline entry for a retired kind red-lines"
else
  fail "retired-kind baseline not caught: rc=$rc out='$out'"
fi
rm -rf "$repo"

# A bare token / F_KIND-style mention is not coverage — require Finding: <kind>.
repo="$(mk_tree)"
write_collector "$repo" covered-one token-only-kind
{
  printf '# synthetic suite\n'
  for kind in "${PAD_KINDS[@]}" covered-one; do
    printf 'assert_contains "x" "Finding: %s"\n' "$kind"
  done
  printf 'F_KIND=(token-only-kind)\n'
  printf '# comment names token-only-kind without asserting collector output\n'
} >"$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh"
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNCOVERED FINDING KIND: token-only-kind"* ]]; then
  ok "F_KIND / comment token does not satisfy coverage"
else
  fail "token-only mention wrongly counted as coverage: rc=$rc out='$out'"
fi
rm -rf "$repo"

# A shorter kind must not be covered by a Finding: assertion for a longer kind
# that shares its prefix (worktree-root-conformance vs -summary).
repo="$(mk_tree)"
write_collector "$repo" covered-one short-kind short-kind-extra
{
  printf '# synthetic suite\n'
  for kind in "${PAD_KINDS[@]}" covered-one short-kind-extra; do
    printf 'assert_contains "x" "Finding: %s"\n' "$kind"
  done
} >"$repo/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh"
out="$(run_check "$repo" 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"UNCOVERED FINDING KIND: short-kind"* ]]; then
  ok "prefix of a longer Finding: kind does not satisfy coverage"
else
  fail "prefix collision wrongly counted as coverage: rc=$rc out='$out'"
fi
rm -rf "$repo"


# Historical proof (#2656): the gate must go red against the two commits that
# shipped the coverage gap. Point FLEET_FINDING_* at trees extracted from git.
if git rev-parse --verify --quiet "cc58cbc5^{commit}" >/dev/null 2>&1 &&
  git rev-parse --verify --quiet "6f0a3110^{commit}" >/dev/null 2>&1; then
  hist="$(mktemp -d)"
  mkdir -p "$hist/scripts"
  cp "$SCRIPT" "$hist/scripts/check-fleet-finding-test-coverage.sh"
  # Empty baseline: prove the raw invariant fails on both trees.
  : >"$hist/scripts/fleet-finding-test-coverage-baseline.txt"
  for rev in cc58cbc5 6f0a3110; do
    mkdir -p "$hist/$rev/plugins/repo-fleet-hygiene/skills/audit/scripts"
    git show "$rev:plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" \
      >"$hist/$rev/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh"
    git show "$rev:plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh" \
      >"$hist/$rev/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh"
    out="$(
      cd "$hist" &&
        FLEET_FINDING_SCRIPT="$hist/$rev/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" \
          FLEET_FINDING_TEST="$hist/$rev/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh" \
          FLEET_FINDING_COVERAGE_BASELINE="$hist/scripts/fleet-finding-test-coverage-baseline.txt" \
          bash scripts/check-fleet-finding-test-coverage.sh --check 2>&1
    )"
    rc=$?
    if [[ $rc -ne 0 && "$out" == *"UNCOVERED FINDING KIND:"* ]]; then
      ok "historical $rev goes red with empty baseline"
    else
      fail "historical $rev did not go red: rc=$rc out='$out'"
    fi
  done
  # 6f0a3110 specifically lost bare-repo-with-working-tree from the suite.
  out="$(
    cd "$hist" &&
      FLEET_FINDING_SCRIPT="$hist/6f0a3110/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh" \
        FLEET_FINDING_TEST="$hist/6f0a3110/plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh" \
        FLEET_FINDING_COVERAGE_BASELINE="$hist/scripts/fleet-finding-test-coverage-baseline.txt" \
        bash scripts/check-fleet-finding-test-coverage.sh --check 2>&1
  )"
  if [[ "$out" == *"UNCOVERED FINDING KIND: bare-repo-with-working-tree"* ]]; then
    ok "6f0a3110 specifically misses bare-repo-with-working-tree"
  else
    fail "6f0a3110 bare-repo gap not reported: out='$out'"
  fi
  rm -rf "$hist"
else
  # Historical proof-of-red must fail closed when the anchors are unavailable —
  # scoring the skip as ok would let a shallow clone or rewritten history
  # report green while proving nothing (#2807).
  fail "historical proof unavailable (cc58cbc5/6f0a3110 not in this clone)"
fi

# Live tree with the real baseline must pass.
if (cd "$SELF_DIR/.." && bash scripts/check-fleet-finding-test-coverage.sh --check) >/dev/null; then
  ok "repository baseline passes --check"
else
  fail "repository baseline fails --check"
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
