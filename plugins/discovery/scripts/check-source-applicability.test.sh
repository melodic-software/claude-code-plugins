#!/usr/bin/env bash
# Black-box contract test for check-source-applicability.py.
#
# Self-contained and cwd-independent; mutates only its own guarded mktemp dir.
#
# The cases that matter are the ones where a wrong answer is invisible: a source
# written for an older version must never pass as current evidence for a claim
# about a newer one, and a slice this gate cannot read must never pass at all.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-source-applicability.py"

WORK="$(mktemp -d)"
if [[ -z "$WORK" || ! -d "$WORK" ]]; then
  printf 'error: mktemp -d failed; refusing to write fixtures\n' >&2
  exit 2
fi
trap 'rm -rf "$WORK"' EXIT

passes=0
fails=0
pass() {
  printf 'ok   - %s\n' "$1"
  passes=$((passes + 1))
}
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# run <expected-exit> <label> [--err <stderr-substring>] [args...]
# --err also requires stderr to contain the substring, so a case fails for its
# intended rule rather than for any violation at all.
run() {
  local expected="$1" label="$2" want_err=""
  shift 2
  if [[ "${1:-}" == --err ]]; then
    want_err="$2"
    shift 2
  fi
  local err actual
  python3 "$SUT" "$@" >/dev/null 2>"$WORK/stderr"
  actual=$?
  err="$(cat "$WORK/stderr")"
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$label: expected exit $expected, got $actual: $err"
  elif [[ -n "$want_err" && "$err" != *"$want_err"* ]]; then
    fail "$label: stderr lacks '$want_err': $err"
  else
    pass "$label (exit $actual)"
  fi
}

# src <role> <published> <applies_to> <standing>; "-" omits that key.
src() {
  printf '      - url: "https://example.test/doc"\n'
  printf '        tier: 1\n        pool: "docs"\n        measures: "m"\n'
  if [[ "$1" != - ]]; then printf '        role: %s\n' "$1"; fi
  if [[ "$2" != - ]]; then printf '        published: %s\n' "$2"; fi
  if [[ "$3" != - ]]; then printf '        applies_to: %s\n' "$3"; fi
  if [[ "$4" != - ]]; then printf '        standing: %s\n' "$4"; fi
}

# claim <applies_to or -> <sources text>
claim() {
  printf '  - claim: "c"\n    confidence: HIGH\n    tiers: [1, 2]\n'
  if [[ "$1" != - ]]; then printf '    applies_to: %s\n' "$1"; fi
  printf '    sources:\n%s\n' "$2"
  printf '    inference: "i"\n    qualifiers: []\n'
}

# mkslice <name> <evidence_use or -> <claims text>; prints the slice dir.
mkslice() {
  local d="$WORK/$1"
  mkdir -p "$d"
  {
    printf -- '---\ntopic: t\n'
    if [[ "$2" != - ]]; then printf 'evidence_use: %s\n' "$2"; fi
    printf -- '---\n# Index\n'
  } >"$d/RESEARCH.md"
  printf -- '---\ntopic: t\nsection: s\nabstract: a\nclaims:\n%s\nproduced_by: p\n---\n# Body\n' \
    "$3" >"$d/RESEARCH-s.md"
  printf '%s' "$d"
}

PRIMARY="$(src primary 2025-01-01 'ExampleLib 9' current)"
V9='ExampleLib 9'

# one_source <name> <role> <published> <applies_to> <standing> [claim-applies_to]
# A slice with the standard primary plus one extra source on a claim.
one_source() {
  local c="${6:-$V9}"
  local p="$PRIMARY"
  if [[ "$c" != "$V9" ]]; then p="$(src primary 2025-01-01 "$c" current)"; fi
  mkslice "$1" - "$(claim "$c" "$p
$(src "$2" "$3" "$4" "$5")")"
}

# --- clean slices -----------------------------------------------------------

clean="$(mkslice clean - "$(claim "$V9" "$PRIMARY
$(src corroborator 2024-06 'ExampleLib 8-10' current)")")"
run 0 "clean slice, internal" "$clean"
clean_pub="$(mkslice clean-pub publish "$(claim "$V9" "$PRIMARY
$(src corroborator 2024 'ExampleLib 9' current)")")"
run 0 "clean slice, publish" "$clean_pub"

# --- published (R2) ---------------------------------------------------------

PUB_BAD='source 2: published missing, invalid or in the future'
DERIVES_HIST='standing is current but derives historical'
DERIVES_CUR='standing is historical but derives current'

run 1 "missing published" --err "$PUB_BAD" "$(one_source pub-missing corroborator - "$V9" current)"
run 1 "bad published" --err "$PUB_BAD: 2025-02-30" "$(one_source pub-bad corroborator 2025-02-30 "$V9" current)"
run 1 "non-date published" --err "$PUB_BAD: soon" "$(one_source pub-word corroborator soon "$V9" current)"
run 1 "future published" --err "$PUB_BAD: 2999-01-01" "$(one_source pub-future corroborator 2999-01-01 "$V9" current)"

# --- applies_to (R1, R3) ----------------------------------------------------

run 1 "missing claim applies_to" --err 'claim 1: applies_to missing or unparsable: None' \
  "$(mkslice claim-at-missing - "$(claim - "$PRIMARY")")"
run 1 "unparsable claim applies_to" --err 'claim 1: applies_to missing or unparsable: ExampleLib' \
  "$(mkslice claim-at-bad - "$(claim 'ExampleLib' "$PRIMARY")")"
run 1 "missing source applies_to" --err 'source 2: applies_to missing or unparsable: None' \
  "$(one_source src-at-missing corroborator 2025-01-01 - current)"
run 1 "unparsable source applies_to" --err 'source 2: applies_to missing or unparsable: ExampleLib ten' \
  "$(one_source src-at-bad corroborator 2025-01-01 'ExampleLib ten' current)"
run 1 "inverted source range" --err 'source 2: applies_to missing or unparsable: ExampleLib 10-8' \
  "$(one_source src-at-inverted corroborator 2025-01-01 'ExampleLib 10-8' historical)"

# --- standing and role (R4, R5) ---------------------------------------------

run 1 "bad standing" --err 'source 2: standing must be current or historical: stale' \
  "$(one_source bad-standing corroborator 2025-01-01 "$V9" stale)"
run 1 "missing standing" --err 'source 2: standing must be current or historical: None' \
  "$(one_source no-standing corroborator 2025-01-01 "$V9" -)"
run 1 "bad role" --err 'source 2: role must be primary or corroborator: secondary' \
  "$(one_source bad-role secondary 2025-01-01 "$V9" current)"
run 1 "two primaries" --err 'expected exactly one primary source, found 2' \
  "$(one_source two-primaries primary 2025-01-01 "$V9" current)"
run 1 "zero primaries" --err 'expected exactly one primary source, found 0' \
  "$(mkslice zero-primaries - "$(claim "$V9" "$(src corroborator 2025-01-01 "$V9" current)")")"

# --- primary (R7) -----------------------------------------------------------

run 1 "undated primary on versioned claim" --err 'source 1: primary source must be dated' \
  "$(mkslice undated-primary - "$(claim "$V9" "$(src primary undated "$V9" current)")")"
run 1 "undated primary on version-independent claim, internal" --err 'source 1: primary source must be dated' \
  "$(mkslice undated-primary-vi - "$(claim version-independent "$(src primary undated version-independent current)")")"
run 1 "historical primary" --err 'source 1: primary source must be current' \
  "$(mkslice historical-primary - "$(claim "$V9" "$(src primary 2025-01-01 'ExampleLib 2' historical)")")"

# An undated primary is one fault: "must be dated" fires, "must be current"
# does not, and a stored label that already says historical adds nothing more.
undated_hist="$(mkslice undated-primary-hist - "$(claim "$V9" "$(src primary undated "$V9" historical)")")"
out="$(python3 "$SUT" "$undated_hist" 2>"$WORK/stderr")"
err="$(cat "$WORK/stderr")"
if [[ "$out" == 'status=fail violations=1 '* && "$err" == *'must be dated'* ]]; then
  pass "undated primary stored historical reports one violation"
else
  fail "undated primary stored historical should report one violation: $out / $err"
fi
out="$(python3 "$SUT" "$WORK/undated-primary" 2>"$WORK/stderr")"
err="$(cat "$WORK/stderr")"
if [[ "$out" == 'status=fail violations=2 '* && "$err" == *"$DERIVES_HIST"* && "$err" != *'must be current'* ]]; then
  pass "undated primary stored current reports the mismatch and the date only"
else
  fail "undated primary stored current should report two violations: $out / $err"
fi

# --- derived standing (R6) --------------------------------------------------

run 1 "old-major source stored current on newer-major claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source old-major-current corroborator 2020-01-01 'ExampleLib 2' current)"
run 0 "old-major source stored historical" \
  "$(one_source old-major-historical corroborator 2020-01-01 'ExampleLib 2' historical)"
run 1 "version-independent source stored current on versioned claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source vi-on-versioned corroborator 2025-01-01 version-independent current)"
run 0 "version-independent source stored historical on versioned claim" \
  "$(one_source vi-on-versioned-hist corroborator 2025-01-01 version-independent historical)"
run 1 "different-product source stored current" --err "source 2: $DERIVES_HIST" \
  "$(one_source other-product corroborator 2025-01-01 'OtherLib 9' current)"
run 0 "different-product source stored historical" \
  "$(one_source other-product-hist corroborator 2025-01-01 'OtherLib 9' historical)"
run 0 "range source covers the claim" \
  "$(one_source range-covers corroborator 2025-01-01 'ExampleLib 8-10' current)"
run 0 "plus source covers the claim" \
  "$(one_source plus-covers corroborator 2025-01-01 'ExampleLib 8+' current)"
run 1 "narrower source stored current" --err "source 2: $DERIVES_HIST" \
  "$(one_source narrower corroborator 2025-01-01 'ExampleLib 9.4' current)"
run 0 "narrower source stored historical" \
  "$(one_source narrower-hist corroborator 2025-01-01 'ExampleLib 9.4' historical)"
run 1 "undated source stored current on versioned claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source undated-versioned corroborator undated "$V9" current)"
run 0 "product compared case- and space-insensitively" \
  "$(one_source product-case corroborator 2025-01-01 'examplelib   9' current)"
run 0 "dotted prefix covers a patch claim" \
  "$(one_source prefix-covers corroborator 2025-01-01 'Tool 2.1' current 'Tool 2.1.211')"
run 1 "sibling minor stored current on a patch claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source prefix-miss corroborator 2025-01-01 'Tool 2.0' current 'Tool 2.1.211')"
run 0 "sibling minor stored historical on a patch claim" \
  "$(one_source prefix-miss-hist corroborator 2025-01-01 'Tool 2.0' historical 'Tool 2.1.211')"
run 1 "source stored historical that derives current" --err "source 2: $DERIVES_CUR" \
  "$(one_source under-claims corroborator 2025-01-01 'ExampleLib 8-10' historical)"
run 1 "exact source stored current on a range claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source range-claim-exact corroborator 2025-01-01 "$V9" current 'ExampleLib 8-10')"
run 0 "exact source stored historical on a range claim" \
  "$(one_source range-claim-exact-hist corroborator 2025-01-01 "$V9" historical 'ExampleLib 8-10')"
run 1 "bounded source stored current on an open claim" --err "source 2: $DERIVES_HIST" \
  "$(one_source open-claim-bounded corroborator 2025-01-01 'ExampleLib 9-12' current 'ExampleLib 9+')"
run 0 "bounded source stored historical on an open claim" \
  "$(one_source open-claim-bounded-hist corroborator 2025-01-01 'ExampleLib 9-12' historical 'ExampleLib 9+')"
run 0 "open source covers an open claim" \
  "$(one_source open-claim-open corroborator 2025-01-01 'ExampleLib 8+' current 'ExampleLib 9+')"

vi_corrob() {
  mkslice "$1" "$2" "$(claim version-independent "$(src primary 2025-01-01 version-independent current)
$(src corroborator undated version-independent current)")"
}
run 0 "undated current corroborator on version-independent claim, internal" "$(vi_corrob vi-undated -)"
run 1 "undated current corroborator on version-independent claim, publish" \
  --err "source 2: $DERIVES_HIST" "$(vi_corrob vi-undated-pub publish)"
run 0 "versioned source covers a version-independent claim" \
  "$(one_source vi-claim-versioned corroborator 2025-01-01 'OtherLib 3' current version-independent)"

# --- evidence_use -----------------------------------------------------------

run 1 "--expect-evidence-use publish against index without evidence_use" \
  --err 'index records internal, caller expects publish' "$clean" --expect-evidence-use publish
run 0 "--expect-evidence-use internal against index without evidence_use" \
  "$clean" --expect-evidence-use internal
run 0 "--expect-evidence-use publish against publish index" \
  "$clean_pub" --expect-evidence-use publish
out="$(python3 "$SUT" "$(vi_corrob vi-undated-flag -)" --expect-evidence-use publish 2>/dev/null)"
want='status=fail violations=2 evidence_use=publish claims=1 sources=2 historical=1'
if [[ "$out" == "$want" ]]; then
  pass "--expect-evidence-use publish grades an internal index under publish"
else
  fail "--expect-evidence-use publish should grade under publish: want '$want', got '$out'"
fi
run 2 "bad --expect-evidence-use value" "$clean" --expect-evidence-use draft
run 2 "--expect-evidence-use without a value" "$clean" --expect-evidence-use
run 2 "bad evidence_use in the index" "$(mkslice bad-mode draft "$(claim "$V9" "$PRIMARY")")"
empty_mode="$(mkslice empty-mode - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nevidence_use:\n---\n' >"$empty_mode/RESEARCH.md"
run 2 "empty evidence_use in the index" --err 'evidence_use must be internal or publish' "$empty_mode"
run 0 "quoted evidence_use in the index" "$(mkslice quoted-mode '"publish"' "$(claim "$V9" "$PRIMARY")")"

# --- parsing ----------------------------------------------------------------

run 0 "quoted values parse" "$(mkslice quoted - "$(claim '"ExampleLib 9"' "$(src "'primary'" '"2025-01-01"' "'ExampleLib 8+'" '"current"')")")"
run 0 "trailing comments ignored" "$(mkslice comments - "$(claim "ExampleLib 9   # target" "$(src primary 2025-01-01 'ExampleLib 9 # same' current)")")"

crlf="$(mkslice crlf - "$(claim "$V9" "$PRIMARY")")"
sed 's/$/\r/' "$crlf/RESEARCH-s.md" >"$crlf/crlf.tmp" && mv "$crlf/crlf.tmp" "$crlf/RESEARCH-s.md"
run 0 "CRLF sidecar parses" "$crlf"
crlf_bad="$(mkslice crlf-bad - "$(claim "$V9" "$(src primary 2025-01-01 'ExampleLib 2' current)")")"
sed 's/$/\r/' "$crlf_bad/RESEARCH-s.md" >"$crlf_bad/crlf.tmp" && mv "$crlf_bad/crlf.tmp" "$crlf_bad/RESEARCH-s.md"
run 1 "CRLF sidecar still graded" --err "source 1: $DERIVES_HIST" "$crlf_bad"

bom="$(mkslice bom - "$(claim "$V9" "$PRIMARY")")"
{ printf '\xef\xbb\xbf'; cat "$bom/RESEARCH-s.md"; } >"$bom/bom.tmp" && mv "$bom/bom.tmp" "$bom/RESEARCH-s.md"
run 0 "BOM sidecar parses" "$bom"

# An all-Gap run: every sidecar says claims: [] and the slice still passes.
no_claims="$WORK/no-claims"
mkdir -p "$no_claims"
printf -- '---\ntopic: t\n---\n' >"$no_claims/RESEARCH.md"
printf -- '---\ntopic: t\nclaims: []\n---\n' >"$no_claims/RESEARCH-a.md"
printf -- '---\ntopic: t\nclaims:\n---\n' >"$no_claims/RESEARCH-b.md"
run 0 "sidecars with empty claims lists" "$no_claims"

# A bad sidecar in a sub-slice is never read.
nested="$(mkslice nested - "$(claim "$V9" "$PRIMARY")")"
mkdir -p "$nested/sub"
printf 'no front matter\n' >"$nested/sub/RESEARCH-x.md"
run 0 "sub-slices are not recursed into" "$nested"

# --- ungradeable ------------------------------------------------------------

run 2 "missing slice" "$WORK/does-not-exist"
no_index="$(mkslice no-index - "$(claim "$V9" "$PRIMARY")")"
mv "$no_index/RESEARCH.md" "$no_index/INDEX.md"
run 2 "no index" "$no_index"
no_sidecar="$(mkslice no-sidecar - "$(claim "$V9" "$PRIMARY")")"
mv "$no_sidecar/RESEARCH-s.md" "$no_sidecar/notes.md"
run 2 "no sidecars" "$no_sidecar"
no_fm="$(mkslice no-fm - "$(claim "$V9" "$PRIMARY")")"
printf '# Just a body\n' >"$no_fm/RESEARCH-s.md"
run 2 "sidecar without front matter" "$no_fm"
unterminated="$(mkslice unterminated - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nclaims: []\n' >"$unterminated/RESEARCH-s.md"
run 2 "unterminated front matter" "$unterminated"
bad_item="$(mkslice bad-item - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nclaims:\n  - text: "c"\n    applies_to: ExampleLib 9\n---\n' >"$bad_item/RESEARCH-s.md"
run 2 "claims item that is not a claim" --err 'does not start with claim:' "$bad_item"
key_order="$(mkslice key-order - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nclaims:\n  - applies_to: ExampleLib 9\n    claim: "c"\n---\n' >"$key_order/RESEARCH-s.md"
run 2 "claim whose first key is not claim:" --err 'does not start with claim:' "$key_order"

no_key="$(mkslice no-claims-key - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nsection: s\n---\n' >"$no_key/RESEARCH-s.md"
run 2 "sidecar without a claims: key" --err 'no claims: key' "$no_key"
cased_key="$(mkslice cased-claims-key - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nClaims: []\n---\n' >"$cased_key/RESEARCH-s.md"
run 2 "misspelled Claims: key" --err 'no claims: key' "$cased_key"

tabbed="$(mkslice tabbed - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nclaims:\n  - claim: "c"\n\t  applies_to: ExampleLib 9\n---\n' >"$tabbed/RESEARCH-s.md"
run 2 "tab in front-matter indentation" --err 'tab in indentation' "$tabbed"
tabbed_index="$(mkslice tabbed-index - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\n\tnote: x\n---\n' >"$tabbed_index/RESEARCH.md"
run 2 "tab in index front-matter indentation" --err 'tab in indentation' "$tabbed_index"

run 2 "duplicate key in a claim" --err 'duplicate key applies_to' \
  "$(mkslice dup-claim-key - "$(claim "$V9" "    applies_to: OtherLib 1
$PRIMARY")")"
run 2 "duplicate sources key in a claim" --err 'duplicate key sources' \
  "$(mkslice dup-sources-key - "$(claim "$V9" "$PRIMARY
    sources:
$PRIMARY")")"
run 2 "duplicate key in a source" --err 'duplicate key role' \
  "$(mkslice dup-source-key - "$(claim "$V9" "$PRIMARY
        role: corroborator")")"
dup_claims="$(mkslice dup-claims - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: t\nclaims: []\nclaims:\n  - claim: "c"\n    applies_to: ExampleLib 9\n---\n' >"$dup_claims/RESEARCH-s.md"
run 2 "duplicate top-level claims key" --err 'duplicate top-level key claims' "$dup_claims"
dup_mode="$(mkslice dup-mode publish "$(claim "$V9" "$PRIMARY")")"
printf -- '---\nabstract: a\nevidence_use: publish\nevidence_use: internal\n---\n' >"$dup_mode/RESEARCH.md"
run 2 "duplicate top-level evidence_use key" --err 'duplicate top-level key evidence_use' "$dup_mode"
non_utf8="$(mkslice non-utf8 - "$(claim "$V9" "$PRIMARY")")"
printf -- '---\ntopic: \xff\xfe\n---\n' >"$non_utf8/RESEARCH-s.md"
run 2 "non-UTF-8 sidecar" "$non_utf8"
run 0 "--help" --help
run 2 "no args"
run 2 "unknown flag" "$clean" --strict
run 2 "two slice dirs" "$clean" "$clean_pub"

# --- summary lines ----------------------------------------------------------

out="$(python3 "$SUT" "$clean" 2>/dev/null)"
want='status=pass evidence_use=internal claims=1 sources=2 historical=0'
if [[ "$out" == "$want" ]]; then
  pass "pass summary line"
else
  fail "pass summary line: want '$want', got '$out'"
fi

old_major="$WORK/old-major-current"
out="$(python3 "$SUT" "$old_major" 2>/dev/null)"
want='status=fail violations=1 evidence_use=internal claims=1 sources=2 historical=1'
if [[ "$out" == "$want" ]]; then
  pass "fail summary line"
else
  fail "fail summary line: want '$want', got '$out'"
fi

err="$(python3 "$SUT" "$old_major" 2>&1 >/dev/null)"
if [[ "$err" == *"RESEARCH-s.md: claim 1: source 2: "* ]]; then
  pass "violation names file, claim and source"
else
  fail "violation should name file, claim and source: got '$err'"
fi

out="$(python3 "$SUT" "$WORK/does-not-exist" 2>/dev/null)"
if [[ "$out" == "status=ungradeable" ]]; then
  pass "ungradeable summary line"
else
  fail "ungradeable summary line: got '$out'"
fi

total=$((passes + fails))
if [[ "$fails" -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$total"
  exit 0
fi
printf '\n%d of %d case(s) failed.\n' "$fails" "$total" >&2
exit 1
