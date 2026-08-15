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
assert_contains "the owner carries an as-of date" "$owner_text" "as-of **2026-08-15**"
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

# 3b. The unconditional expiry must be able to fire (#2767).
#
# The literal-presence checks above guard the stamp's *shape*. They never parse
# a date, so the suite stays green forever after the expiry passes — the one
# failure mode the stamp exists to prevent. Parse both arms out of the owner;
# enforce the date arm against an injectable "today"; assert the version arm is
# present and shaped (CI has no live Claude Code version to compare against).

# nesting_invariant_expiry_date_passed <expiry-YYYY-MM-DD> <today-YYYY-MM-DD>
# — return 0 when today is on or after the expiry (stamp is stale), 1 when still
# fresh. Pure string compare of ISO dates.
nesting_invariant_expiry_date_passed() {
  local expiry="$1" today="$2"
  [[ "$today" > "$expiry" || "$today" == "$expiry" ]]
}

# Parse: as-of **YYYY-MM-DD** — require the stamp delimiters so a nearby date
# cannot satisfy the check as a substring.
if [[ "$owner_text" =~ as-of[[:space:]]+\*\*([0-9]{4}-[0-9]{2}-[0-9]{2})\*\* ]]; then
  as_of_date="${BASH_REMATCH[1]}"
  pass "as-of date is parseable ($as_of_date)"
else
  fail "as-of date is parseable (YYYY-MM-DD)" "matched" "no match"
  as_of_date=""
fi

# Parse unconditional expiry arms from the owner sentence:
#   **Unconditional expiry.** **2.1.244, or 2026-11-07 — whichever comes first.**
# Match the complete bold arm (not an arbitrary substring) so malformed tokens
# such as `2.1.244.1`, `v2.1.244`, or overlong dates cannot pass shape checks.
expiry_version=""
expiry_date=""
if [[ "$owner_text" =~ Unconditional[[:space:]]+expiry\.\*\*[[:space:]]*\*\*([0-9]+\.[0-9]+\.[0-9]+),[[:space:]]+or[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+[—-] ]]; then
  expiry_version="${BASH_REMATCH[1]}"
  expiry_date="${BASH_REMATCH[2]}"
elif [[ "$owner_text" =~ Unconditional[[:space:]]+expiry[^\n]*\*\*([0-9]+\.[0-9]+\.[0-9]+),[[:space:]]+or[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  # Same whole-arm capture with slightly looser heading markup tolerance.
  expiry_version="${BASH_REMATCH[1]}"
  expiry_date="${BASH_REMATCH[2]}"
fi

if [[ -n "$expiry_version" && -n "$expiry_date" ]]; then
  pass "unconditional expiry version arm is parseable ($expiry_version)"
  pass "unconditional expiry date arm is parseable ($expiry_date)"
else
  fail "unconditional expiry carries a parseable version arm (N.N.N)" "matched" "no match"
  fail "unconditional expiry carries a parseable date arm (YYYY-MM-DD)" "matched" "no match"
fi

# Version arm: present and shaped — do not evaluate against a live Claude Code
# version (CI does not have one). The shape guard stops the arm vanishing.
if [[ -n "$expiry_version" && "$expiry_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  pass "expiry version arm matches N.N.N shape ($expiry_version)"
else
  fail "expiry version arm matches N.N.N shape" "N.N.N" "${expiry_version:-empty}"
fi

# Date arm: enforce. Inject today so the red path is exercised in-suite.
if [[ -n "$expiry_date" ]]; then
  today="$(date -u +%Y-%m-%d)"
  if nesting_invariant_expiry_date_passed "$expiry_date" "$today"; then
    fail "nesting-invariant stamp date arm is still fresh (today < $expiry_date)" \
      "fresh (today before $expiry_date)" "EXPIRED (today=$today) — run fixtures/nesting-invariant-probe.sh and refresh SKILL.md"
  else
    pass "nesting-invariant stamp date arm is still fresh (today=$today < $expiry_date)"
  fi

  # Red path: a synthetic post-expiry "today" must be detected. A comparison
  # nobody has exercised is the same class of defect as the one being fixed.
  if nesting_invariant_expiry_date_passed "$expiry_date" "2099-01-01"; then
    pass "expiry date comparison detects a synthetic post-expiry today"
  else
    fail "expiry date comparison detects a synthetic post-expiry today" \
      "expired-detected" "still-fresh"
  fi

  # Sanity: a synthetic pre-expiry today must NOT trip.
  if nesting_invariant_expiry_date_passed "$expiry_date" "2000-01-01"; then
    fail "expiry date comparison stays fresh for a synthetic pre-expiry today" \
      "still-fresh" "expired-detected"
  else
    pass "expiry date comparison stays fresh for a synthetic pre-expiry today"
  fi

  # as-of should not sit after the expiry (stamp would be born stale).
  if [[ -n "$as_of_date" ]]; then
    if [[ "$as_of_date" > "$expiry_date" ]]; then
      fail "as-of date is not after the unconditional expiry date" \
        "as-of <= $expiry_date" "as-of=$as_of_date"
    else
      pass "as-of date is not after the unconditional expiry date"
    fi
  fi
fi

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
