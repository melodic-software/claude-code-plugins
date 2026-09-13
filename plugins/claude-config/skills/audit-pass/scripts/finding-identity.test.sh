#!/usr/bin/env bash
# Regression tests for finding-identity.sh (self-contained — ships with the plugin).
#
# Most cases here assert a §1 ASSERTION by number, because the assertions are the
# contract and a test that only round-trips the script proves nothing about it.
# Two are NEGATIVE tests in the sense this repo means it: they mutate a copy of
# the script to delete exactly one check and assert the mutated copy reaches the
# outcome the real one refuses.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/finding-identity.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_ne() {
  if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1" "expected a difference, both were: $2"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

run() { bash "$SCRIPT" "$@"; }

ref_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# --- Normalization, v1 ------------------------------------------------------

assert_eq "trailing whitespace is stripped and internal runs collapse to one space" \
  "one two three" "$(run normalize --excerpt '  one   two
three  ')"

# 1.8: case is PRESERVED, because these surfaces carry code and identifiers.
assert_eq "case is preserved" "MixedCase Identifier" \
  "$(run normalize --excerpt 'MixedCase Identifier')"

# 1.8: backticks and the text they delimit are preserved, so literal text quoted
# AS AN EXAMPLE of an import cannot hash identically to a real import.
# shellcheck disable=SC2016  # the backticks are literal excerpt content, not a substitution
BACKTICKED=$(run anchor --excerpt '`@README`')
BARE=$(run anchor --excerpt '@README')
assert_ne "1.8: a backticked @README and a bare one produce different anchors" \
  "$BACKTICKED" "$BARE"

# 1.8: a block-level HTML comment outside a fence changes no anchor; the same
# edit inside a fence does.
PLAIN=$(run anchor --excerpt 'rule text')
COMMENTED=$(run anchor --excerpt 'rule <!-- note to self --> text')
assert_eq "1.8: an HTML comment outside a fence does not change the anchor" "$PLAIN" "$COMMENTED"
IN_FENCE=$(run anchor --excerpt 'rule <!-- note to self --> text' --in-fence)
assert_ne "1.8: inside a fence the same comment is content and does change it" "$PLAIN" "$IN_FENCE"

assert_eq "surrounding emphasis markers are stripped, nested ones too" \
  "emphasized" "$(run normalize --excerpt '***emphasized***')"
assert_eq "an emphasis marker inside the excerpt is content and stays" \
  "a *b* c" "$(run normalize --excerpt 'a *b* c')"

# --- anchor/v1 shape --------------------------------------------------------

A=$(run anchor --excerpt 'some rule' --heading-path 'Rules')
if [[ "$A" =~ ^e:[0-9a-f]{12}:[0-9a-f]{8}$ ]]; then
  pass "an excerpt anchor is e:<12hex>:<8hex>"
else
  fail "an excerpt anchor is e:<12hex>:<8hex>" "got: $A"
fi
assert_eq "a whole-surface anchor is bare s:, content-free" "s:" "$(run anchor --whole)"
rc=0
run anchor --whole --excerpt 'x' >/dev/null 2>&1 || rc=$?
assert_exit "--whole with an excerpt is refused: a whole-surface anchor is content-free" 2 "$rc"

# 1.10: two identical excerpts under DIFFERENT heading paths get distinct anchors.
D1=$(run anchor --excerpt 'never do X' --heading-path 'Rules')
D2=$(run anchor --excerpt 'never do X' --heading-path 'Gotchas')
assert_ne "1.10: identical excerpts under different heading paths differ in <n>" "$D1" "$D2"
assert_eq "1.10: and they agree on the excerpt half" "${D1%%:*}" "${D2%%:*}"

# 1.10a: under the SAME heading path they collide, deliberately. No positional
# scheme can separate them without reintroducing the suppression-transfer bug.
S1=$(run anchor --excerpt 'never do X' --heading-path 'Rules')
S2=$(run anchor --excerpt 'never   do X' --heading-path 'Rules')
assert_eq "1.10a: two identical normalized excerpts under one heading path collide" "$S1" "$S2"

# 1.2: inserting an unrelated paragraph above a finding changes nothing, because
# the discriminator is the ENCLOSING HEADING PATH and not the neighbouring text.
assert_eq "1.2: the anchor does not depend on neighbouring content" \
  "$D1" "$(run anchor --excerpt 'never do X' --heading-path 'Rules')"

NO_HEADING=$(run anchor --excerpt 'never do X')
SENTINEL_EXPECTED=$(printf '\x00' | ref_sha)
assert_eq "a surface with no heading above the excerpt uses the 0x00 sentinel" \
  "${SENTINEL_EXPECTED:0:8}" "${NO_HEADING##*:}"

# --- finding_id/v1 ----------------------------------------------------------

ID_AB=$(run finding-id --check p/s/c --claim claim.one --site 'a.md=s:' --site 'b.md=s:')
ID_REVERSED=$(run finding-id --check p/s/c --claim claim.one --site 'b.md=s:' --site 'a.md=s:')
# 1.4: a pairwise finding discovered one way round and the other is ONE id.
assert_eq "1.4: site order does not change finding_id" "$ID_AB" "$ID_REVERSED"
assert_eq "finding_id is 16 hex characters" 16 "${#ID_AB}"

# Independently re-derived, so the test is not the script checking itself.
EXPECTED_ID=$(printf 'p/s/c\x1fclaim.one\x1fa.md\x1fs:\x1fb.md\x1fs:' | ref_sha)
assert_eq "finding_id equals the independently derived pinned body" \
  "${EXPECTED_ID:0:16}" "$ID_AB"

# 1.7: editing any line of a surface leaves an s: finding's id unchanged;
# renaming that surface changes it.
ID_RENAMED=$(run finding-id --check p/s/c --claim claim.one --site 'renamed.md=s:' --site 'b.md=s:')
assert_ne "1.7: renaming a surface changes an s: finding's id" "$ID_AB" "$ID_RENAMED"

ID_OTHER_CLAIM=$(run finding-id --check p/s/c --claim claim.two --site 'a.md=s:' --site 'b.md=s:')
assert_ne "a different claim is a different finding" "$ID_AB" "$ID_OTHER_CLAIM"

# --- group/v1 ---------------------------------------------------------------

G=$(run group-id --check p/s/c --claim claim.one)
if [[ "$G" =~ ^g:[0-9a-f]{16}$ ]]; then
  pass "group/v1 is g:<16hex>"
else
  fail "group/v1 is g:<16hex>" "got: $G"
fi
# 1.12: group is unchanged by adding, removing, or fixing any site, because it is
# derived from check and claim ALONE.
assert_eq "1.12: group does not depend on any site" "$G" "$(run group-id --check p/s/c --claim claim.one)"
assert_ne "a different claim is a different group" "$G" "$(run group-id --check p/s/c --claim claim.two)"

# --- The emitter guard ------------------------------------------------------

if ! command -v python3 >/dev/null 2>&1; then
  printf 'SKIP: python3 absent, the emitter guard cases do not run\n'
else
  mk_record() {
    # $1 check, $2 claim, then site specs; prints a valid record.
    local check="$1" claim="$2"
    shift 2
    local sites_json="" spec surface anchor first=1 id
    local site_args=()
    for spec in "$@"; do
      surface="${spec%%=*}"
      anchor="${spec#*=}"
      if [[ "$first" -eq 1 ]]; then first=0; else sites_json="$sites_json,"; fi
      sites_json="$sites_json{\"surface\":\"$surface\",\"anchor\":\"$anchor\"}"
      site_args+=(--site "$spec")
    done
    local pairwise="false"
    if [[ $# -eq 2 ]]; then pairwise="true"; fi
    id=$(run finding-id --check "$check" --claim "$claim" "${site_args[@]}")
    printf '{"record":"finding","identity":{"check":"%s","claim":"%s","pairwise":%s,"sites":[%s]},"finding_id/v1":"%s"}' \
      "$check" "$claim" "$pairwise" "$sites_json" "$id"
  }

  VALID_ONE=$(mk_record p/s/c claim.one 'a.md=e:aaaaaaaaaaaa:bbbbbbbb')
  rc=0
  OUT=$(run validate-record --record "$VALID_ONE" 2>&1) || rc=$?
  assert_exit "a well-formed one-site finding passes the guard" 0 "$rc"
  assert_eq "and says so" "ok" "$OUT"

  # 1.13: identity absent or null.
  rc=0
  OUT=$(run validate-record --record '{"record":"finding","identity":null,"lane":"skills"}' 2>&1) || rc=$?
  assert_exit "1.13: identity null is refused with the record verdict" 4 "$rc"
  assert_contains "and the refusal names what was wrong" "$OUT" "identity was absent or null"

  rc=0
  OUT=$(run validate-record --record '{"record":"finding","lane":"skills"}' 2>&1) || rc=$?
  assert_exit "1.13: identity absent is refused too" 4 "$rc"

  # 1.13: three or more sites.
  THREE=$(mk_record p/s/c claim.one 'a.md=e:aaaaaaaaaaaa:bbbbbbbb' 'b.md=e:cccccccccccc:dddddddd' 'c.md=e:eeeeeeeeeeee:ffffffff')
  rc=0
  OUT=$(run validate-record --record "$THREE" 2>&1) || rc=$?
  assert_exit "1.13: three sites is a hard error" 4 "$rc"
  assert_contains "and the refusal names the split the lane owed" "$OUT" "split"

  # 1.13: two sites without a pairwise declaration.
  TWO_NOT_PAIRWISE='{"record":"finding","identity":{"check":"p/s/c","claim":"claim.one","pairwise":false,"sites":[{"surface":"a.md","anchor":"e:aaaaaaaaaaaa:bbbbbbbb"},{"surface":"b.md","anchor":"e:cccccccccccc:dddddddd"}]},"finding_id/v1":"0000000000000000"}'
  rc=0
  OUT=$(run validate-record --record "$TWO_NOT_PAIRWISE" 2>&1) || rc=$?
  assert_exit "1.13: two sites without a pairwise claim is refused" 4 "$rc"
  assert_contains "and the refusal names the remedy" "$OUT" "split them per site"

  # 1.6: an s: anchor in a two-site finding.
  S_TWO_SITE='{"record":"finding","identity":{"check":"p/s/c","claim":"claim.one","pairwise":true,"sites":[{"surface":"a.md","anchor":"s:"},{"surface":"b.md","anchor":"e:cccccccccccc:dddddddd"}]},"finding_id/v1":"0000000000000000"}'
  rc=0
  OUT=$(run validate-record --record "$S_TWO_SITE" 2>&1) || rc=$?
  assert_exit "1.6: an s: anchor with two sites is a hard error" 4 "$rc"

  # 1.3: free prose in claim.
  PROSE='{"record":"finding","identity":{"check":"p/s/c","claim":"this instruction is too prescriptive","pairwise":false,"sites":[{"surface":"a.md","anchor":"s:"}]},"finding_id/v1":"0000000000000000"}'
  rc=0
  OUT=$(run validate-record --record "$PROSE" 2>&1) || rc=$?
  assert_exit "1.3: free prose in claim is a hard error" 4 "$rc"

  # 1.13: a stored id that disagrees with its own constituents. A suppression
  # keyed to the stored id would never match the finding it names.
  WRONG_ID='{"record":"finding","identity":{"check":"p/s/c","claim":"claim.one","pairwise":false,"sites":[{"surface":"a.md","anchor":"s:"}]},"finding_id/v1":"deadbeefdeadbeef"}'
  rc=0
  OUT=$(run validate-record --record "$WRONG_ID" 2>&1) || rc=$?
  assert_exit "1.13: a finding_id disagreeing with its constituents is refused" 4 "$rc"
  assert_contains "and both values are named" "$OUT" "deadbeefdeadbeef"

  # A note is validated against the NOTE shape: a note_id and no identity block.
  rc=0
  OUT=$(run validate-record --record '{"record":"note","note_id":"n1","names":["aaaa","bbbb"]}' 2>&1) || rc=$?
  assert_exit "a well-formed overlap note passes" 0 "$rc"
  rc=0
  OUT=$(run validate-record --record '{"record":"note","note_id":"n1","identity":{}}' 2>&1) || rc=$?
  assert_exit "a note carrying an identity block is refused: notes are outside D(R)" 4 "$rc"
  rc=0
  OUT=$(run validate-record --record '{"record":"note"}' 2>&1) || rc=$?
  assert_exit "a note with no note_id is refused" 4 "$rc"

  rc=0
  run validate-record --record '{bad json}' >/dev/null 2>&1 || rc=$?
  assert_exit "a malformed record is refused rather than appended" 4 "$rc"

  # NEGATIVE: delete the site-count check and the three-site record sails
  # through. A bound whose removal changes nothing is not a bound.
  COPY="$TEST_TMPDIR/no-site-cap.sh"
  sed '/if len(sites) > 2:/,+4d' "$SCRIPT" >"$COPY"
  rc=0
  bash "$COPY" validate-record --record "$THREE" >/dev/null 2>&1 || rc=$?
  assert_exit "without the site cap a three-site record is accepted" 0 "$rc"

  # NEGATIVE: delete the identity-null check and the null record sails through.
  COPY2="$TEST_TMPDIR/no-identity-check.sh"
  sed '/if "identity" not in rec or rec\["identity"\] is None:/,+1d' "$SCRIPT" >"$COPY2"
  rc=0
  OUT=$(bash "$COPY2" validate-record --record '{"record":"finding","identity":null}' 2>&1) || rc=$?
  assert_ne "without the identity check the null record no longer hits that refusal" \
    "invalid: a finding record requires an identity block; identity was absent or null" "$OUT"
fi

# --- Usage ------------------------------------------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
assert_exit "no command exits 2" 2 "$rc"
rc=0
run nonsense >/dev/null 2>&1 || rc=$?
assert_exit "an unknown command exits 2" 2 "$rc"
rc=0
run finding-id --check p/s/c --claim claim.one >/dev/null 2>&1 || rc=$?
assert_exit "finding-id with no site exits 2" 2 "$rc"
rc=0
run finding-id --check p/s/c --claim claim.one --site 'no-equals-sign' >/dev/null 2>&1 || rc=$?
assert_exit "a --site that is not <surface>=<anchor> exits 2" 2 "$rc"
rc=0
run --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
