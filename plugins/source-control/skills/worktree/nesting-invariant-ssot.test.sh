#!/usr/bin/env bash
# nesting-invariant-ssot.test.sh — the mechanism claim has ONE owner.
#
# The nesting invariant justifies a machine-wide worktree-placement rule enforced
# by a fail-closed hook. Restated copies drift into undated absolutes, and a
# pointer can then land a reader on a copy asserting a freshness it has no basis
# for. Updating every copy is not the fix; one owner and pointers is. This test
# is what stops the re-drift: it fails when a second site states the mechanism,
# so the next person to explain it in place has to point instead.
#
# CHANGELOG.md is excluded throughout. A changelog is a historical record and its
# past entries must keep their original wording — rewriting them to satisfy a
# freshness rule would be the more serious defect.
#
# Environment:
#   NESTING_INVARIANT_INSTALLED_VERSION  Installed Claude Code version (N.N.N) to
#     check against the stamp's version arm. The suite never probes the host CLI,
#     so the result does not depend on where it runs; unset skips that arm with a
#     counted skip.
# test-scope: plugins/source-control/*
# test-scope: .gitattributes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OWNER_REL="skills/worktree/SKILL.md"
SELF_REL="skills/worktree/nesting-invariant-ssot.test.sh"

# How long the owner's dated "expired, pending re-probe" marker is honored. Past
# this the suite fails until the re-probe refreshes the stamp or the marker is
# re-dated on purpose.
MARKER_MAX_AGE_DAYS=30

FAILED=0
CASE_NUM=0
# shellcheck source=../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

owner_text="$(<"$PLUGIN_ROOT/$OWNER_REL")"

# Lists the plugin files containing a fixed string, with the exclusion set every
# case needs: CHANGELOG.md (see above) and this test, which necessarily quotes
# every phrase it polices.
grep_sites() {
  git -C "$PLUGIN_ROOT" grep -lIF "$1" -- \
    ":(exclude)CHANGELOG.md" ":(exclude)$SELF_REL" 2>/dev/null || true
}

# 1. The undated absolute is gone everywhere.
#
# This exact sentence is the drift shape: it states a causal mechanism with no
# date, no basis and no expiry. The owner does not use it either — the owner
# states what was actually observed (`path_glob_match` naming a file) rather
# than a generalized consequence.
mapfile -t ABSOLUTES < <(grep_sites "a read matching a path-scoped rule's glob also loads")
assert_eq "the undated absolute form of the claim appears nowhere" "0" "${#ABSOLUTES[@]}"
((${#ABSOLUTES[@]} == 0)) || printf '      sites: %s\n' "${ABSOLUTES[*]}" >&2

# 2. The measured statement lives at exactly one site, and it is the owner.
#
# Keyed on the instrument's own event name: anything restating what the trace
# observed has to name it, and a paraphrase that avoids the word is no longer
# stating the measurement.
mapfile -t MEASURED < <(grep_sites "path_glob_match")
assert_eq "the measurement is stated at exactly one site" "1" "${#MEASURED[@]}"
((${#MEASURED[@]} == 1)) || printf '      sites: %s\n' "${MEASURED[*]}" >&2
if ((${#MEASURED[@]} == 1)); then
  assert_eq "that site is the owner" "$OWNER_REL" "${MEASURED[0]}"
fi

# 3. The owner carries what a pointer promises the reader will be there.
assert_contains "the owner carries the anchor every pointer cites" \
  "$owner_text" "### The nesting invariant, dated measurement"
assert_contains "the owner carries an as-of date" "$owner_text" "as-of **2026-09-30**"
assert_contains "the owner carries an unconditional expiry, not only event triggers" \
  "$owner_text" "Unconditional expiry"
# Keep the reasoning attached to the expiry, or a later reader deletes it as
# redundant with the event triggers.
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
#   **Unconditional expiry.** **2.1.305, or 2026-12-29 — whichever comes first.**
# Match the complete bold arm (not an arbitrary substring) so malformed tokens
# such as `2.1.244.1`, `v2.1.244`, or overlong dates cannot pass shape checks.
# The second alternative is the same whole-arm capture with slightly looser
# heading markup tolerance; whichever alternative matches leaves its captures in
# BASH_REMATCH for the shared read.
expiry_version=""
expiry_date=""
if [[ "$owner_text" =~ Unconditional[[:space:]]+expiry\.\*\*[[:space:]]*\*\*([0-9]+\.[0-9]+\.[0-9]+),[[:space:]]+or[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+[—-] ]] ||
  [[ "$owner_text" =~ Unconditional[[:space:]]+expiry[^\n]*\*\*([0-9]+\.[0-9]+\.[0-9]+),[[:space:]]+or[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
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

# iso_day_number <YYYY-MM-DD>: days since 1970-01-01 (days-from-civil), so the
# marker age needs neither GNU nor BSD date.
iso_day_number() {
  local y=$((10#${1:0:4})) m=$((10#${1:5:2})) d=$((10#${1:8:2}))
  ((m <= 2)) && y=$((y - 1))
  local era=$((y / 400))
  local yoe=$((y - era * 400))
  local doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  echo $((era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468))
}

# nesting_invariant_marker_honored <marker-YYYY-MM-DD> <today-YYYY-MM-DD>
# <max-age-days>: return 0 while the marker is at most max-age days old. One day
# of future skew is tolerated (a marker dated in a timezone ahead of UTC); a
# marker dated further ahead is not honored.
nesting_invariant_marker_honored() {
  local age=$(($(iso_day_number "$2") - $(iso_day_number "$1")))
  ((age >= -1 && age <= $3))
}

# An expired stamp is acceptable only while the owner's dated marker is fresh. The
# marker is the honest state between an arm firing and an authenticated re-probe
# landing; undated, it would turn both arms from fail to pass forever, so it
# carries its date and stops being honored MARKER_MAX_AGE_DAYS later.
today="$(date -u +%Y-%m-%d)"
marker_pattern='\*\*Stamp status: expired, pending re-probe, marked ([0-9]{4}-[0-9]{2}-[0-9]{2})\.\*\*'
stamp_marked_expired=false
if [[ "$owner_text" =~ $marker_pattern ]]; then
  marker_date="${BASH_REMATCH[1]}"
  if nesting_invariant_marker_honored "$marker_date" "$today" "$MARKER_MAX_AGE_DAYS"; then
    stamp_marked_expired=true
    pass "expired-stamp marker (marked $marker_date) is within $MARKER_MAX_AGE_DAYS days of today ($today)"
  else
    fail "expired-stamp marker is within $MARKER_MAX_AGE_DAYS days of today" \
      "marked within $MARKER_MAX_AGE_DAYS days of $today" \
      "marked $marker_date; run fixtures/nesting-invariant-probe.sh under an authenticated CLI and refresh SKILL.md, or re-date the marker on purpose"
  fi
elif [[ "$owner_text" == *"Stamp status: expired"* ]]; then
  fail "expired-stamp marker carries its date" \
    "**Stamp status: expired, pending re-probe, marked YYYY-MM-DD.**" "undated or malformed marker"
fi

# Red path: a synthetic today past the marker's age must not be honored, nor a
# marker dated far ahead of today, and the boundary must be exact across a month,
# a leap day and a year end. A check nobody has exercised is the same class of
# defect as the static marker this replaced.
if nesting_invariant_marker_honored "2026-09-27" "2099-01-01" "$MARKER_MAX_AGE_DAYS"; then
  fail "marker age check rejects a synthetic today past the marker's age" "not honored" "honored"
else
  pass "marker age check rejects a synthetic today past the marker's age"
fi
if nesting_invariant_marker_honored "2099-01-01" "$today" "$MARKER_MAX_AGE_DAYS"; then
  fail "marker age check rejects a marker dated far in the future" "not honored" "honored"
else
  pass "marker age check rejects a marker dated far in the future"
fi
if nesting_invariant_marker_honored "2026-01-01" "2026-01-31" 30 &&
  ! nesting_invariant_marker_honored "2026-01-01" "2026-02-01" 30 &&
  nesting_invariant_marker_honored "2028-02-28" "2028-03-29" 30 &&
  ! nesting_invariant_marker_honored "2028-02-28" "2028-03-30" 30 &&
  nesting_invariant_marker_honored "2026-12-15" "2027-01-14" 30 &&
  ! nesting_invariant_marker_honored "2026-12-15" "2027-01-15" 30; then
  pass "marker age check is exact at the boundary across month, leap-day and year ends"
else
  fail "marker age check is exact at the boundary across month, leap-day and year ends" \
    "30 days honored, 31 not" "boundary off"
fi

# nesting_invariant_version_passed <expiry-N.N.N> <installed-N.N.N> — return 0
# when installed is at or past the expiry version.
nesting_invariant_version_passed() {
  local -a e i
  local n
  IFS=. read -r -a e <<<"$1"
  IFS=. read -r -a i <<<"$2"
  for n in 0 1 2; do
    ((10#${i[n]:-0} > 10#${e[n]:-0})) && return 0
    ((10#${i[n]:-0} < 10#${e[n]:-0})) && return 1
  done
  return 0
}

# Version arm: enforce against the version the caller supplies. The host CLI is
# never probed, so the result does not depend on which Claude Code is installed.
installed_version="${NESTING_INVARIANT_INSTALLED_VERSION:-}"
if [[ -z "$installed_version" ]]; then
  skip_case "nesting-invariant version arm: NESTING_INVARIANT_INSTALLED_VERSION is unset"
elif [[ -n "$expiry_version" ]]; then
  if ! nesting_invariant_version_passed "$expiry_version" "$installed_version"; then
    pass "nesting-invariant stamp version arm is still fresh (installed $installed_version < $expiry_version)"
  elif $stamp_marked_expired; then
    pass "installed $installed_version is past the $expiry_version arm and the owner's dated marker is fresh"
  else
    fail "installed Claude Code is past the version arm but the owner has no fresh dated expired marker" \
      "before $expiry_version, or a marker within $MARKER_MAX_AGE_DAYS days in the owner" \
      "installed=$installed_version — run fixtures/nesting-invariant-probe.sh and refresh SKILL.md"
  fi
fi

if nesting_invariant_version_passed "2.1.244" "2.1.278" &&
  nesting_invariant_version_passed "2.1.244" "2.1.244" &&
  ! nesting_invariant_version_passed "2.1.244" "2.1.99" &&
  ! nesting_invariant_version_passed "2.1.244" "2.1.243"; then
  pass "expiry version comparison orders releases numerically"
else
  fail "expiry version comparison orders releases numerically" "numeric order" "lexical or broken"
fi

# Date arm: enforce. Inject today so the red path is exercised in-suite.
if [[ -n "$expiry_date" ]]; then
  if ! nesting_invariant_expiry_date_passed "$expiry_date" "$today"; then
    pass "nesting-invariant stamp date arm is still fresh (today=$today < $expiry_date)"
  elif $stamp_marked_expired; then
    pass "today ($today) is past the $expiry_date arm and the owner's dated marker is fresh"
  else
    fail "nesting-invariant stamp date arm is still fresh (today < $expiry_date)" \
      "fresh (today before $expiry_date)" "EXPIRED (today=$today) — run fixtures/nesting-invariant-probe.sh and refresh SKILL.md"
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
mapfile -t POINTERS < <(grep_sites "The nesting invariant, dated measurement")
if ((${#POINTERS[@]} >= 5)); then
  pass "the former restatement sites cite the owner by name (${#POINTERS[@]} files)"
else
  fail "restatements were rewritten as pointers, not dropped" ">=5 files" "${#POINTERS[@]}"
fi

printf '\n%d case(s), %d failure(s), %d optional skip(s), %d discriminating skip(s)\n' \
  "$CASE_NUM" "$FAILED" "$SKIP_CASES" "$DISCRIMINATING_SKIP_CASES"
[[ $FAILED -eq 0 ]] || exit 1
