#!/usr/bin/env bash
# Black-box contract test for check-skill-leaf-names.sh.
#
# Self-contained and cwd-independent: builds a throwaway plugins/ tree with
# fixture skills, runs the checker against it, and asserts on exit code +
# output. Mutates only its own mktemp dir. The SUT resolves its paths relative
# to its own location, so the fixture tree carries a copy of it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-skill-leaf-names.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts"
cp "$SUT_SRC" "$TMP/scripts/check-skill-leaf-names.sh"
SUT="$TMP/scripts/check-skill-leaf-names.sh"
REGISTRY="$TMP/scripts/skill-leaf-name-registry.txt"

make_skill() {
  # plugin, skill
  mkdir -p "$TMP/plugins/$1/skills/$2"
  printf -- '---\nname: %s\ndescription: "fixture"\n---\n' "$2" >"$TMP/plugins/$1/skills/$2/SKILL.md"
}

run() { bash "$SUT" "$@" 2>&1; }

# A directory without SKILL.md must not count as a skill.
mkdir -p "$TMP/plugins/alpha/skills/not-a-skill"

make_skill alpha solo
make_skill alpha shared
make_skill beta shared
make_skill gamma shared

# 1. discover lists a collision with all its owners.
out="$(run)"
if grep -q 'shared' <<<"$out" && grep -q '3 plugins' <<<"$out"; then
  pass "discover lists a collision with its owner count"
else
  fail "discover should list shared across 3 plugins: $out"
fi

# 2. A leaf name owned by only one plugin is not a collision.
if ! grep -q 'solo' <<<"$out"; then
  pass "single-owner leaf name is not reported"
else
  fail "solo should not be reported as a collision: $out"
fi

# 3. A directory without SKILL.md is not counted as a skill.
if ! grep -q 'not-a-skill' <<<"$out"; then
  pass "directory without SKILL.md is not counted"
else
  fail "not-a-skill should be ignored: $out"
fi

# 4. --check fails on an unregistered collision.
: >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'is not registered' <<<"$out"; then
  pass "unregistered collision fails --check"
else
  fail "unregistered collision should fail (rc=$rc): $out"
fi

# 5. --check passes once the collision is registered with its owner set, and
#    comments/blank lines in the registry are ignored.
printf '# a comment\n\n  shared alpha,beta,gamma  # trailing comment\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'are registered' <<<"$out"; then
  pass "registered collision passes --check (comments and whitespace ignored)"
else
  fail "registered collision should pass (rc=$rc): $out"
fi

# 5b. Owner order in the registry does not matter — sets are compared, not lists.
printf 'shared gamma,alpha,beta\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "owner set comparison is order-independent"
else
  fail "reordered owner set should pass (rc=$rc): $out"
fi

# 5c. A registered name whose owner set GREW fails — the first registration must
#     not pre-authorize later owners joining on the original grounds.
printf 'shared alpha,beta\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'is registered for' <<<"$out"; then
  pass "a new owner joining a registered collision fails"
else
  fail "grown owner set should fail (rc=$rc): $out"
fi

# 5d. A bare name with no owner field is rejected, so the old format cannot
#     silently keep passing as an open registration.
printf 'shared\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'without an owner set' <<<"$out"; then
  pass "registration without an owner set is rejected"
else
  fail "bare-name entry should fail (rc=$rc): $out"
fi

# 5e. `*` accepts any owner set — and must reach the comparison as a literal
#     rather than being pathname-expanded against the cwd.
printf 'shared *\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'are registered' <<<"$out"; then
  pass "wildcard owner set accepts any owners (literal, not glob-expanded)"
else
  fail "wildcard entry should pass (rc=$rc): $out"
fi

# 6. Stale guard: a registry entry that no longer collides fails.
printf 'shared\nvanished\n' >"$REGISTRY"
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'no longer carried by 2+ plugins' <<<"$out"; then
  pass "stale registry entry fails --check"
else
  fail "stale entry should fail (rc=$rc): $out"
fi

# 7. A NEW collision on an unregistered name fails even when others are
#    registered — the regression-critical path this gate exists for.
printf 'shared\n' >"$REGISTRY"
make_skill alpha newdupe
make_skill beta newdupe
out="$(run --check)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'newdupe' <<<"$out"; then
  pass "a newly introduced collision fails while existing ones stay registered"
else
  fail "new collision should fail (rc=$rc): $out"
fi

# 8. Unknown mode is a usage error, not a silent pass.
bash "$SUT" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
