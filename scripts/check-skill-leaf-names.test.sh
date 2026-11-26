#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-skill-leaf-names.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP="" CLEAN=""

fixture_tree::build TMP --sut "$SUT_SRC" --plugins
SUT="$TMP/scripts/check-skill-leaf-names.sh"
REGISTRY="$TMP/scripts/skill-leaf-name-registry.txt"

make_skill() {
  local plugin="$1" skill="$2"
  mkdir -p "$TMP/plugins/$plugin/skills/$skill"
  printf -- '---\nname: %s\ndescription: "fixture"\n---\n' "$skill" >"$TMP/plugins/$plugin/skills/$skill/SKILL.md"
}

run() { bash "$SUT" "$@" 2>&1; }

mkdir -p "$TMP/plugins/alpha/skills/not-a-skill"

make_skill alpha solo
make_skill alpha shared
make_skill beta shared
make_skill gamma shared

out="$(run)"
if grep -q 'shared' <<<"$out" && grep -q '3 plugins' <<<"$out"; then
  ok "discover lists a collision with its owner count"
else
  fail "discover should list shared across 3 plugins: $out"
fi

if ! grep -q 'solo' <<<"$out"; then
  ok "single-owner leaf name is not reported"
else
  fail "solo should not be reported as a collision: $out"
fi

if ! grep -q 'not-a-skill' <<<"$out"; then
  ok "directory without SKILL.md is not counted"
else
  fail "not-a-skill should be ignored: $out"
fi

: >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'is not registered' <<<"$out"; then
  ok "unregistered collision fails --check"
else
  fail "unregistered collision should fail (rc=$rc): $out"
fi

printf '# a comment\n\n  shared alpha,beta,gamma  # trailing comment\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'are registered' <<<"$out"; then
  ok "registered collision passes --check (comments and whitespace ignored)"
else
  fail "registered collision should pass (rc=$rc): $out"
fi

printf 'shared gamma,alpha,beta\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "owner set comparison is order-independent"
else
  fail "reordered owner set should pass (rc=$rc): $out"
fi

printf 'shared alpha,beta\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'is registered for' <<<"$out"; then
  ok "a new owner joining a registered collision fails"
else
  fail "grown owner set should fail (rc=$rc): $out"
fi

printf 'shared\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'without an owner set' <<<"$out"; then
  ok "registration without an owner set is rejected"
else
  fail "bare-name entry should fail (rc=$rc): $out"
fi

printf 'shared *\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'are registered' <<<"$out"; then
  ok "wildcard owner set accepts any owners (literal, not glob-expanded)"
else
  fail "wildcard entry should pass (rc=$rc): $out"
fi

printf 'shared alpha,beta\nshared alpha,beta,gamma\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'registers shared more than once' <<<"$out"; then
  ok "a leaf name registered twice fails"
else
  fail "duplicate registry entry should fail (rc=$rc): $out"
fi

printf 'zeta *\nshared alpha,beta,gamma\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'lists shared after zeta' <<<"$out"; then
  ok "an unsorted registry fails"
else
  fail "unsorted registry should fail (rc=$rc): $out"
fi

printf 'shared\nvanished\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'no longer carried by 2+ plugins' <<<"$out"; then
  ok "stale registry entry fails --check"
else
  fail "stale entry should fail (rc=$rc): $out"
fi
if grep -q "STALE BASELINE: .*: 'vanished'" <<<"$out"; then
  ok "the stale diagnostic carries the shared STALE BASELINE prefix"
else
  fail "stale diagnostic should carry the shared prefix: $out"
fi

printf 'shared alpha,beta,gamma' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a final registry entry with no trailing newline is loaded"
else
  fail "unterminated final entry should be loaded (rc=$rc): $out"
fi

printf 'shared\n' >"$REGISTRY"
make_skill alpha newdupe
make_skill beta newdupe
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'newdupe' <<<"$out"; then
  ok "a newly introduced collision fails while existing ones stay registered"
else
  fail "new collision should fail (rc=$rc): $out"
fi

fixture_tree::build CLEAN --sut "$SUT_SRC" --plugins
mkdir -p "$CLEAN/plugins/solo/skills/only"
printf -- '---\nname: only\ndescription: "fixture"\n---\n' >"$CLEAN/plugins/solo/skills/only/SKILL.md"
: >"$CLEAN/scripts/skill-leaf-name-registry.txt"

out="$(bash "$CLEAN/scripts/check-skill-leaf-names.sh" --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'unbound variable' <<<"$out"; then
  ok "zero collisions with an empty registry passes --check"
else
  fail "zero-collision state should pass (rc=$rc): $out"
fi

out="$(bash "$CLEAN/scripts/check-skill-leaf-names.sh" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'No cross-plugin skill leaf-name collisions' <<<"$out"; then
  ok "zero collisions reports cleanly in discover mode"
else
  fail "zero-collision discover should report cleanly (rc=$rc): $out"
fi
rm -rf "$CLEAN"

bash "$SUT" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
