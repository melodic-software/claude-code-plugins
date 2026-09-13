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

# 1.8: the WHOLE whitespace class collapses, not just tab and newline. A set
# missing `\r` leaves `a\r\nb` as `a\r b` where `a\nb` becomes `a b`, so two
# checkouts differing only in line-ending handling anchor differently and their
# suppression ids stop matching. Compared as ANCHORS, which is where the
# divergence would be permanent.
LF_ANCHOR=$(run anchor --excerpt "$(printf 'a\nb')")
CRLF_ANCHOR=$(run anchor --excerpt "$(printf 'a\r\nb')")
CR_ANCHOR=$(run anchor --excerpt "$(printf 'a\rb')")
assert_eq "1.8: a CRLF excerpt anchors identically to the same LF excerpt" \
  "$LF_ANCHOR" "$CRLF_ANCHOR"
assert_eq "1.8: a bare CR collapses like any other whitespace run" \
  "$LF_ANCHOR" "$CR_ANCHOR"
assert_eq "1.8: a form feed and a vertical tab collapse too" \
  "$LF_ANCHOR" "$(run anchor --excerpt "$(printf 'a\f\vb')")"
assert_eq "1.8: a mixed whitespace run still collapses to exactly one space" \
  "a b" "$(run normalize --excerpt "$(printf 'a \r\n\t\v\f  b')")"

# NEGATIVE: narrow the set back to tab and newline and the CRLF excerpt anchors
# differently from the LF one. A class whose narrowing changes nothing is not
# doing the collapsing.
COPY_WS="$TEST_TMPDIR/partial-ws-class.sh"
sed "s/tr '\\\\t\\\\n\\\\v\\\\f\\\\r' '     '/tr '\\\\n\\\\t' '  '/" "$SCRIPT" >"$COPY_WS"
assert_ne "without the full class CRLF and LF anchor differently" \
  "$(bash "$COPY_WS" anchor --excerpt "$(printf 'a\nb')")" \
  "$(bash "$COPY_WS" anchor --excerpt "$(printf 'a\r\nb')")"

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

  # --- The anchor grammar, in full --------------------------------------------
  # A prefix test on `e:` accepts any non-empty string starting with it, so
  # `e:garbage` reaches an id derived from a string no anchor version produces.
  # The id is DERIVED for each anchor rather than hardcoded. A fixed placeholder
  # id disagrees with its own constituents, so the consistency check refuses the
  # record before the anchor is ever examined: every assertion below would then
  # pass with the grammar bug present, testing the wrong refusal. Deriving it
  # leaves the anchor as the only thing that can refuse these records.
  mk_anchor_record() {
    local anchor="$1" id
    id="$(run finding-id --check 'p/s/c' --claim 'claim.one' --site "a.md=$anchor")"
    printf '{"record":"finding","identity":{"check":"p/s/c","claim":"claim.one","pairwise":false,"sites":[{"surface":"a.md","anchor":"%s"}]},"finding_id/v1":"%s"}' \
      "$anchor" "$id"
  }
  for BAD_ANCHOR in 'e:garbage' 'e:' 'e:aaaaaaaaaaaa' 'e:aaaaaaaaaaaa:bbbbbbb' \
    'e:aaaaaaaaaaaa:bbbbbbbbb' 'e:AAAAAAAAAAAA:bbbbbbbb' 'e:zzzzzzzzzzzz:bbbbbbbb' \
    'e:aaaaaaaaaaaa:bbbbbbbb:cc' 's:something' 's' 'x:aaaaaaaaaaaa:bbbbbbbb'; do
    rc=0
    OUT=$(run validate-record --record "$(mk_anchor_record "$BAD_ANCHOR")" 2>&1) || rc=$?
    assert_exit "an anchor outside the grammar is refused: $BAD_ANCHOR" 4 "$rc"
  done
  rc=0
  OUT=$(run validate-record --record "$(mk_anchor_record 'e:garbage')" 2>&1) || rc=$?
  assert_contains "and the refusal names the grammar" "$OUT" 'e:<12hex>:<8hex>'

  # Both legal forms still pass, so the grammar narrowed nothing it should not.
  rc=0
  run validate-record --record "$(mk_record p/s/c claim.one 'a.md=e:0123456789ab:0a1b2c3d')" \
    >/dev/null 2>&1 || rc=$?
  assert_exit "a full e: anchor still passes" 0 "$rc"
  rc=0
  run validate-record --record "$(mk_record p/s/c claim.one 'a.md=s:')" >/dev/null 2>&1 || rc=$?
  assert_exit "the bare whole-surface anchor still passes" 0 "$rc"

  # NEGATIVE: restore the prefix test and `e:garbage` is accepted again.
  COPY3="$TEST_TMPDIR/prefix-anchor-check.sh"
  sed 's/if not ANCHOR_RE.match(anchor):/if not (anchor == "s:" or anchor.startswith("e:")):/' \
    "$SCRIPT" >"$COPY3"
  GARBAGE_ID=$(run finding-id --check p/s/c --claim claim.one --site 'a.md=e:garbage')
  GARBAGE_REC="{\"record\":\"finding\",\"identity\":{\"check\":\"p/s/c\",\"claim\":\"claim.one\",\"pairwise\":false,\"sites\":[{\"surface\":\"a.md\",\"anchor\":\"e:garbage\"}]},\"finding_id/v1\":\"$GARBAGE_ID\"}"
  rc=0
  bash "$COPY3" validate-record --record "$GARBAGE_REC" >/dev/null 2>&1 || rc=$?
  assert_exit "with only the prefix test e:garbage is accepted" 0 "$rc"
  rc=0
  run validate-record --record "$GARBAGE_REC" >/dev/null 2>&1 || rc=$?
  assert_exit "and the real guard refuses the same record" 4 "$rc"
fi

# --- guarded-append: the guard is ON the append path ------------------------
# A guard a lane can complete the documented steps without invoking is a guard
# that does not exist, and the record it would have refused is permanent.

if ! command -v python3 >/dev/null 2>&1; then
  printf 'SKIP: python3 absent, guarded-append cannot run its guard\n'
else
  GA_DATA="$TEST_TMPDIR/ga-data"
  GA_RUN="$GA_DATA/runs/demo/run-ga"
  bash "$SCRIPT_DIR/run-state.sh" lease acquire \
    --run-dir "$GA_RUN" --run-id run-ga --epoch 2 --plugin-data "$GA_DATA" >/dev/null 2>&1

  # A stub appender that records being reached. The guard must refuse BEFORE it.
  STUB="$TEST_TMPDIR/stub-appender.sh"
  STUB_LOG="$TEST_TMPDIR/stub.log"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "reached %%s\\n" "$*" >>"%s"\n' "$STUB_LOG"
  } >"$STUB"

  GA_BAD='{"record":"finding","identity":null,"lane":"skills"}'
  rc=0
  OUT=$(AUDIT_PASS_APPENDER="$STUB" run guarded-append --run-dir "$GA_RUN" \
    --record "$GA_BAD" --epoch 2 2>&1) || rc=$?
  assert_exit "guarded-append refuses an invalid record with the record verdict" 4 "$rc"

  # The guard runs before the APPENDER'S OWN precondition, not merely before the
  # write. Checked the other way round, an unreadable appender turns a bad record
  # into exit 2, reporting the operator's environment for a fault that is in the
  # lane's output. Nothing is written on either ordering, so only the exit code
  # distinguishes them.
  rc=0
  OUT=$(AUDIT_PASS_APPENDER=/nonexistent/appender run guarded-append \
    --run-dir "$GA_RUN" --record "$GA_BAD" --epoch 2 2>&1) || rc=$?
  assert_exit "an invalid record exits 4 even when the appender is unreadable" 4 "$rc"
  assert_contains "and the message is the record's fault, not the appender's" \
    "$OUT" "identity was absent or null"
  assert_contains "and names what was wrong" "$OUT" "identity was absent or null"
  assert_eq "and the appender was never reached" "0" \
    "$(if [[ -f "$STUB_LOG" ]]; then wc -l <"$STUB_LOG" | tr -d ' '; else printf '0'; fi)"

  # The same record through the real append path: refused, and no partial exists
  # for a bare `partial append` to have written into.
  GA_PARTIAL="$GA_RUN/findings.partial.2.jsonl"
  rc=0
  run guarded-append --run-dir "$GA_RUN" --record "$GA_BAD" --epoch 2 >/dev/null 2>&1 || rc=$?
  assert_exit "the default appender is the sibling run-state.sh, and the guard still refuses" 4 "$rc"
  assert_eq "no partial was written by the refused append" "" \
    "$(ls "$GA_RUN"/findings.partial.*.jsonl 2>/dev/null || true)"

  # NEGATIVE: a bare `partial append`, which is what the skill used to prescribe,
  # accepts the very same record. That is the defect the guard closes.
  rc=0
  bash "$SCRIPT_DIR/run-state.sh" partial append --run-dir "$GA_RUN" \
    --record "$GA_BAD" --epoch 2 >/dev/null 2>&1 || rc=$?
  assert_exit "a bare partial append accepts the null-identity record" 0 "$rc"
  rm -f "$GA_RUN"/findings.partial.*.jsonl

  # A valid record goes all the way through and lands in the writer's epoch file.
  GA_GOOD=$(mk_record p/s/c claim.one 'a.md=e:aaaaaaaaaaaa:bbbbbbbb')
  rc=0
  run guarded-append --run-dir "$GA_RUN" --record "$GA_GOOD" --epoch 2 >/dev/null 2>&1 || rc=$?
  assert_exit "a valid record is appended" 0 "$rc"
  assert_eq "into the file named for the epoch the writer holds" "$GA_GOOD" \
    "$(cat "$GA_PARTIAL" 2>/dev/null)"

  # The half that proves the guard is ON the path rather than beside it: against
  # a partial that ALREADY has rows, a refused record leaves the artifact
  # byte-for-byte and line-for-line what it was.
  GA_BYTES_BEFORE=$(wc -c <"$GA_PARTIAL" | tr -d ' ')
  GA_LINES_BEFORE=$(wc -l <"$GA_PARTIAL" | tr -d ' ')
  # Each rejection carries its OWN label. Three assertions sharing one name make
  # a failure report ambiguous about which input regressed, and a reader
  # comparing two runs by counting FAIL lines rather than reading their names
  # cannot tell a fixed case from a newly broken one.
  GA_REJECT_CASES=(
    "null identity:$GA_BAD"
    "an anchor outside the grammar:$(mk_anchor_record 'e:garbage')"
    'a finding_id disagreeing with its constituents:{"record":"finding","identity":{"check":"p/s/c","claim":"claim.one","pairwise":false,"sites":[{"surface":"a.md","anchor":"s:"}]},"finding_id/v1":"deadbeefdeadbeef"}'
  )
  for GA_CASE in "${GA_REJECT_CASES[@]}"; do
    GA_LABEL="${GA_CASE%%:*}"
    GA_REJECT="${GA_CASE#*:}"
    rc=0
    run guarded-append --run-dir "$GA_RUN" --record "$GA_REJECT" --epoch 2 >/dev/null 2>&1 || rc=$?
    assert_exit "$GA_LABEL is refused with exit 4 against a non-empty partial" 4 "$rc"
  done
  assert_eq "and the partial is unchanged in bytes" \
    "$GA_BYTES_BEFORE" "$(wc -c <"$GA_PARTIAL" | tr -d ' ')"
  assert_eq "and unchanged in lines" \
    "$GA_LINES_BEFORE" "$(wc -l <"$GA_PARTIAL" | tr -d ' ')"

  # FENCED reaches the caller as 3. Collapsing it to 0 would let a superseded run
  # keep dispatching lanes whose output nothing will assemble. The lease holds
  # epoch 2, so an append declaring epoch 1 is a fenced writer.
  rc=0
  OUT=$(run guarded-append --run-dir "$GA_RUN" --record "$GA_GOOD" --epoch 1 2>&1 >/dev/null) || rc=$?
  assert_exit "a fenced append exits 3 through the guard, not 0" 3 "$rc"
  assert_contains "and the fence is still said in words" "$OUT" "FENCED"
  assert_eq "the fenced row went to the writer's own epoch file" "$GA_GOOD" \
    "$(cat "$GA_RUN/findings.partial.1.jsonl" 2>/dev/null)"

  # The appender's own refusals still reach the caller unchanged.
  rc=0
  run guarded-append --run-dir "$TEST_TMPDIR/no-such-run" --record "$GA_GOOD" --epoch 2 \
    >/dev/null 2>&1 || rc=$?
  assert_ne "an appender refusal is not swallowed" 0 "$rc"
  rc=0
  run guarded-append --run-dir "$GA_RUN" --epoch 2 >/dev/null 2>&1 || rc=$?
  assert_exit "guarded-append without --record exits 2" 2 "$rc"
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
