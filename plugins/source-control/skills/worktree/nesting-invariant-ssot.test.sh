#!/usr/bin/env bash
# test-scope: plugins/source-control/*
# test-scope: .gitattributes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OWNER_REL="skills/worktree/reference/nesting-invariant.md"
SELF_REL="skills/worktree/nesting-invariant-ssot.test.sh"

MARKER_MAX_AGE_DAYS=30

FAILED=0
CASE_NUM=0
# shellcheck source=../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

owner_text="$(<"$PLUGIN_ROOT/$OWNER_REL")"

grep_sites() {
  git -C "$PLUGIN_ROOT" grep -lIF "$1" -- \
    ":(exclude)CHANGELOG.md" ":(exclude)$SELF_REL" 2>/dev/null || true
}

mapfile -t ABSOLUTES < <(grep_sites "a read matching a path-scoped rule's glob also loads")
assert_eq "the undated absolute form of the claim appears nowhere" "0" "${#ABSOLUTES[@]}"
((${#ABSOLUTES[@]} == 0)) || printf '      sites: %s\n' "${ABSOLUTES[*]}" >&2

mapfile -t MEASURED < <(grep_sites "path_glob_match")
assert_eq "the measurement is stated at exactly one site" "1" "${#MEASURED[@]}"
((${#MEASURED[@]} == 1)) || printf '      sites: %s\n' "${MEASURED[*]}" >&2
if ((${#MEASURED[@]} == 1)); then
  assert_eq "that site is the owner" "$OWNER_REL" "${MEASURED[0]}"
fi

assert_contains "the owner carries the anchor every pointer cites" \
  "$owner_text" "# The nesting invariant, dated measurement"
assert_contains "the owner carries an as-of date" "$owner_text" "as-of **2026-09-30**"
assert_contains "the owner carries an unconditional expiry, not only event triggers" \
  "$owner_text" "Unconditional expiry"
assert_contains "the expiry states why the event triggers cannot carry this alone" \
  "$owner_text" "incapable of firing on their own"
assert_contains "the owner names the arm as disputed rather than settled" \
  "$owner_text" "disputed, not refuted"
assert_contains "the owner points at the fixture that would adjudicate it" \
  "$owner_text" "nesting-invariant-probe.sh"

nesting_invariant_expiry_date_passed() {
  local expiry="$1" today="$2"
  [[ "$today" > "$expiry" || "$today" == "$expiry" ]]
}

if [[ "$owner_text" =~ as-of[[:space:]]+\*\*([0-9]{4}-[0-9]{2}-[0-9]{2})\*\* ]]; then
  as_of_date="${BASH_REMATCH[1]}"
  pass "as-of date is parseable ($as_of_date)"
else
  fail "as-of date is parseable (YYYY-MM-DD)" "matched" "no match"
  as_of_date=""
fi

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

if [[ -n "$expiry_version" && "$expiry_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  pass "expiry version arm matches N.N.N shape ($expiry_version)"
else
  fail "expiry version arm matches N.N.N shape" "N.N.N" "${expiry_version:-empty}"
fi

iso_day_number() {
  local y=$((10#${1:0:4})) m=$((10#${1:5:2})) d=$((10#${1:8:2}))
  ((m <= 2)) && y=$((y - 1))
  local era=$((y / 400))
  local yoe=$((y - era * 400))
  local doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  echo $((era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468))
}

nesting_invariant_marker_honored() {
  local age=$(($(iso_day_number "$2") - $(iso_day_number "$1")))
  ((age >= -1 && age <= $3))
}

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
      "marked $marker_date; run fixtures/nesting-invariant-probe.sh under an authenticated CLI and refresh reference/nesting-invariant.md, or re-date the marker on purpose"
  fi
elif [[ "$owner_text" == *"Stamp status: expired"* ]]; then
  fail "expired-stamp marker carries its date" \
    "**Stamp status: expired, pending re-probe, marked YYYY-MM-DD.**" "undated or malformed marker"
fi

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
      "installed=$installed_version — run fixtures/nesting-invariant-probe.sh and refresh reference/nesting-invariant.md"
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

if [[ -n "$expiry_date" ]]; then
  if ! nesting_invariant_expiry_date_passed "$expiry_date" "$today"; then
    pass "nesting-invariant stamp date arm is still fresh (today=$today < $expiry_date)"
  elif $stamp_marked_expired; then
    pass "today ($today) is past the $expiry_date arm and the owner's dated marker is fresh"
  else
    fail "nesting-invariant stamp date arm is still fresh (today < $expiry_date)" \
      "fresh (today before $expiry_date)" "EXPIRED (today=$today) — run fixtures/nesting-invariant-probe.sh and refresh reference/nesting-invariant.md"
  fi

  if nesting_invariant_expiry_date_passed "$expiry_date" "2099-01-01"; then
    pass "expiry date comparison detects a synthetic post-expiry today"
  else
    fail "expiry date comparison detects a synthetic post-expiry today" \
      "expired-detected" "still-fresh"
  fi

  if nesting_invariant_expiry_date_passed "$expiry_date" "2000-01-01"; then
    fail "expiry date comparison stays fresh for a synthetic pre-expiry today" \
      "still-fresh" "expired-detected"
  else
    pass "expiry date comparison stays fresh for a synthetic pre-expiry today"
  fi

  if [[ -n "$as_of_date" ]]; then
    if [[ "$as_of_date" > "$expiry_date" ]]; then
      fail "as-of date is not after the unconditional expiry date" \
        "as-of <= $expiry_date" "as-of=$as_of_date"
    else
      pass "as-of date is not after the unconditional expiry date"
    fi
  fi
fi

mapfile -t POINTERS < <(grep_sites "The nesting invariant, dated measurement")
if ((${#POINTERS[@]} >= 5)); then
  pass "the former restatement sites cite the owner by name (${#POINTERS[@]} files)"
else
  fail "restatements were rewritten as pointers, not dropped" ">=5 files" "${#POINTERS[@]}"
fi

printf '\n%d case(s), %d failure(s), %d optional skip(s), %d discriminating skip(s)\n' \
  "$CASE_NUM" "$FAILED" "$SKIP_CASES" "$DISCRIMINATING_SKIP_CASES"
[[ $FAILED -eq 0 ]] || exit 1
