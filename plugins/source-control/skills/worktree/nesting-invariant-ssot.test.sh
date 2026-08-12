#!/usr/bin/env bash
# nesting-invariant-ssot.test.sh — the mechanism claim has ONE owner.
#
# The nesting invariant justifies a machine-wide worktree-placement rule enforced
# by a fail-closed hook. It used to be restated as an undated absolute at 13
# sites against exactly two dated statements, so a pointer could land a reader on
# a copy asserting a freshness it had no basis for. Updating 13 copies is not the
# fix; one owner and twelve pointers is. This test is what stops the re-drift:
# it fails when a second site states the mechanism, so the next person to explain
# it in place has to point instead.
#
# CHANGELOG.md is excluded throughout. A changelog is a historical record and its
# past entries must keep their original wording — rewriting them to satisfy a
# freshness rule would be the more serious defect.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OWNER_REL="skills/worktree/SKILL.md"
SELF_REL="skills/worktree/nesting-invariant-ssot.test.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

owner_text="$(cat "$PLUGIN_ROOT/$OWNER_REL")"

# 1. The undated absolute is gone everywhere.
#
# This exact sentence is the drift shape: it states a causal mechanism with no
# date, no basis and no expiry, and it is what stood at all 13 sites. The owner
# does not use it either — the owner states what was actually observed
# (`path_glob_match` naming a file) rather than a generalized consequence.
mapfile -t ABSOLUTES < <(
  git -C "$PLUGIN_ROOT" grep -lIF "a read matching a path-scoped rule's glob also loads" -- \
    ":(exclude)CHANGELOG.md" ":(exclude)$SELF_REL" 2>/dev/null || true
)
assert_eq "the undated absolute form of the claim appears nowhere" "0" "${#ABSOLUTES[@]}"
((${#ABSOLUTES[@]} == 0)) || printf '      sites: %s\n' "${ABSOLUTES[*]}" >&2

# 2. The measured statement lives at exactly one site, and it is the owner.
#
# Keyed on the instrument's own event name: anything restating what the trace
# observed has to name it, and a paraphrase that avoids the word is no longer
# stating the measurement.
mapfile -t MEASURED < <(
  git -C "$PLUGIN_ROOT" grep -lIF "path_glob_match" -- \
    ":(exclude)CHANGELOG.md" ":(exclude)$SELF_REL" 2>/dev/null || true
)
assert_eq "the measurement is stated at exactly one site" "1" "${#MEASURED[@]}"
((${#MEASURED[@]} == 1)) || printf '      sites: %s\n' "${MEASURED[*]}" >&2
if ((${#MEASURED[@]} == 1)); then
  assert_eq "that site is the owner" "$OWNER_REL" "${MEASURED[0]}"
fi

# 3. The owner carries what a pointer promises the reader will be there.
assert_contains "the owner carries the anchor every pointer cites" \
  "$owner_text" "### The nesting invariant, verified"
assert_contains "the owner carries an as-of date" "$owner_text" "as-of **2026-08-07**"
assert_contains "the owner carries an unconditional expiry, not only event triggers" \
  "$owner_text" "Unconditional expiry"
# Keep the reasoning attached to the expiry, or a later reader deletes it as
# redundant with the event triggers — which is how it went missing the first time.
assert_contains "the expiry states why the event triggers cannot carry this alone" \
  "$owner_text" "incapable of firing on their own"
# The dispute is the reason the fixture exists; an owner that reads as settled
# would re-license the absolutes this test just removed.
assert_contains "the owner names the arm as disputed rather than settled" \
  "$owner_text" "disputed, not refuted"
assert_contains "the owner points at the fixture that would adjudicate it" \
  "$owner_text" "nesting-invariant-probe.sh"

# 4. The restatements became pointers rather than being deleted outright.
mapfile -t POINTERS < <(
  git -C "$PLUGIN_ROOT" grep -lIF "The nesting invariant, verified" -- \
    ":(exclude)CHANGELOG.md" ":(exclude)$SELF_REL" 2>/dev/null || true
)
if ((${#POINTERS[@]} >= 5)); then
  pass "the former restatement sites cite the owner by name (${#POINTERS[@]} files)"
else
  fail "restatements were rewritten as pointers, not dropped" ">=5 files" "${#POINTERS[@]}"
fi

[[ $FAILED -eq 0 ]] || exit 1
