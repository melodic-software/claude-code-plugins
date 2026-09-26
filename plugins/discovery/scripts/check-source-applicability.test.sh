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

# run <expected-exit> <label> [args...]
run() {
  local expected="$1" label="$2"
  shift 2
  local out actual
  out="$(python3 "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label: expected exit $expected, got $actual: $out"
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

run 1 "missing published" "$(one_source pub-missing corroborator - "$V9" current)"
run 1 "bad published" "$(one_source pub-bad corroborator 2025-02-30 "$V9" current)"
run 1 "non-date published" "$(one_source pub-word corroborator soon "$V9" current)"
run 1 "future published" "$(one_source pub-future corroborator 2999-01-01 "$V9" current)"

# --- applies_to (R1, R3) ----------------------------------------------------

run 1 "missing claim applies_to" "$(mkslice claim-at-missing - "$(claim - "$PRIMARY")")"
run 1 "unparseable claim applies_to" "$(mkslice claim-at-bad - "$(claim 'ExampleLib' "$PRIMARY")")"
run 1 "missing source applies_to" "$(one_source src-at-missing corroborator 2025-01-01 - current)"
run 1 "unparseable source applies_to" "$(one_source src-at-bad corroborator 2025-01-01 'ExampleLib ten' current)"
run 1 "inverted source range" "$(one_source src-at-inverted corroborator 2025-01-01 'ExampleLib 10-8' historical)"

# --- standing and role (R4, R5) ---------------------------------------------

run 1 "bad standing" "$(one_source bad-standing corroborator 2025-01-01 "$V9" stale)"
run 1 "missing standing" "$(one_source no-standing corroborator 2025-01-01 "$V9" -)"
run 1 "bad role" "$(one_source bad-role secondary 2025-01-01 "$V9" current)"
run 1 "two primaries" "$(one_source two-primaries primary 2025-01-01 "$V9" current)"
run 1 "zero primaries" "$(mkslice zero-primaries - "$(claim "$V9" "$(src corroborator 2025-01-01 "$V9" current)")")"

# --- primary (R7) -----------------------------------------------------------

run 1 "undated primary on versioned claim" \
  "$(mkslice undated-primary - "$(claim "$V9" "$(src primary undated "$V9" current)")")"
run 1 "undated primary on version-independent claim, internal" \
  "$(mkslice undated-primary-vi - "$(claim version-independent "$(src primary undated version-independent current)")")"
run 1 "historical primary" \
  "$(mkslice historical-primary - "$(claim "$V9" "$(src primary 2025-01-01 'ExampleLib 2' historical)")")"

# --- derived standing (R6) --------------------------------------------------

run 1 "old-major source stored current on newer-major claim" \
  "$(one_source old-major-current corroborator 2020-01-01 'ExampleLib 2' current)"
run 0 "old-major source stored historical" \
  "$(one_source old-major-historical corroborator 2020-01-01 'ExampleLib 2' historical)"
run 1 "version-independent source stored current on versioned claim" \
  "$(one_source vi-on-versioned corroborator 2025-01-01 version-independent current)"
run 0 "version-independent source stored historical on versioned claim" \
  "$(one_source vi-on-versioned-hist corroborator 2025-01-01 version-independent historical)"
run 1 "different-product source stored current" \
  "$(one_source other-product corroborator 2025-01-01 'OtherLib 9' current)"
run 0 "different-product source stored historical" \
  "$(one_source other-product-hist corroborator 2025-01-01 'OtherLib 9' historical)"
run 0 "range source covers the claim" \
  "$(one_source range-covers corroborator 2025-01-01 'ExampleLib 8-10' current)"
run 0 "plus source covers the claim" \
  "$(one_source plus-covers corroborator 2025-01-01 'ExampleLib 8+' current)"
run 1 "narrower source stored current" \
  "$(one_source narrower corroborator 2025-01-01 'ExampleLib 9.4' current)"
run 0 "narrower source stored historical" \
  "$(one_source narrower-hist corroborator 2025-01-01 'ExampleLib 9.4' historical)"
run 1 "undated source stored current on versioned claim" \
  "$(one_source undated-versioned corroborator undated "$V9" current)"
run 0 "product compared case- and space-insensitively" \
  "$(one_source product-case corroborator 2025-01-01 'examplelib   9' current)"
run 0 "dotted prefix covers a patch claim" \
  "$(one_source prefix-covers corroborator 2025-01-01 'Tool 2.1' current 'Tool 2.1.211')"
run 1 "sibling minor stored current on a patch claim" \
  "$(one_source prefix-miss corroborator 2025-01-01 'Tool 2.0' current 'Tool 2.1.211')"
run 0 "sibling minor stored historical on a patch claim" \
  "$(one_source prefix-miss-hist corroborator 2025-01-01 'Tool 2.0' historical 'Tool 2.1.211')"
run 1 "source stored historical that derives current" \
  "$(one_source under-claims corroborator 2025-01-01 'ExampleLib 8-10' historical)"

vi_corrob() {
  mkslice "$1" "$2" "$(claim version-independent "$(src primary 2025-01-01 version-independent current)
$(src corroborator undated version-independent current)")"
}
run 0 "undated current corroborator on version-independent claim, internal" "$(vi_corrob vi-undated -)"
run 1 "undated current corroborator on version-independent claim, publish" "$(vi_corrob vi-undated-pub publish)"
run 0 "versioned source covers a version-independent claim" \
  "$(one_source vi-claim-versioned corroborator 2025-01-01 'OtherLib 3' current version-independent)"

# --- evidence_use -----------------------------------------------------------

run 1 "--expect-evidence-use publish against index without evidence_use" \
  "$clean" --expect-evidence-use publish
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
run 0 "quoted evidence_use in the index" "$(mkslice quoted-mode '"publish"' "$(claim "$V9" "$PRIMARY")")"

# --- parsing ----------------------------------------------------------------

run 0 "quoted values parse" "$(mkslice quoted - "$(claim '"ExampleLib 9"' "$(src "'primary'" '"2025-01-01"' "'ExampleLib 8+'" '"current"')")")"
run 0 "trailing comments ignored" "$(mkslice comments - "$(claim "ExampleLib 9   # target" "$(src primary 2025-01-01 'ExampleLib 9 # same' current)")")"

crlf="$(mkslice crlf - "$(claim "$V9" "$PRIMARY")")"
sed 's/$/\r/' "$crlf/RESEARCH-s.md" >"$crlf/crlf.tmp" && mv "$crlf/crlf.tmp" "$crlf/RESEARCH-s.md"
run 0 "CRLF sidecar parses" "$crlf"
crlf_bad="$(mkslice crlf-bad - "$(claim "$V9" "$(src primary 2025-01-01 'ExampleLib 2' current)")")"
sed 's/$/\r/' "$crlf_bad/RESEARCH-s.md" >"$crlf_bad/crlf.tmp" && mv "$crlf_bad/crlf.tmp" "$crlf_bad/RESEARCH-s.md"
run 1 "CRLF sidecar still graded" "$crlf_bad"

bom="$(mkslice bom - "$(claim "$V9" "$PRIMARY")")"
{ printf '\xef\xbb\xbf'; cat "$bom/RESEARCH-s.md"; } >"$bom/bom.tmp" && mv "$bom/bom.tmp" "$bom/RESEARCH-s.md"
run 0 "BOM sidecar parses" "$bom"

no_claims="$WORK/no-claims"
mkdir -p "$no_claims"
printf -- '---\ntopic: t\n---\n' >"$no_claims/RESEARCH.md"
printf -- '---\ntopic: t\nsection: s\n---\n' >"$no_claims/RESEARCH-a.md"
printf -- '---\ntopic: t\nclaims: []\n---\n' >"$no_claims/RESEARCH-b.md"
run 0 "sidecars with no claims" "$no_claims"

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
run 2 "claims item that is not a claim" "$bad_item"
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
