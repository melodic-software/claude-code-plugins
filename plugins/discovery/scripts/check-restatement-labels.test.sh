#!/usr/bin/env bash
# Black-box contract test for check-restatement-labels.py.
#
# Self-contained and cwd-independent; mutates only its own guarded mktemp dir.
# The two fixture slices under tests/fixtures/restatement-labels/ are read in
# place and never written.
#
# The cases that matter are the ones where a wrong answer is invisible: a
# summary line, handoff bullet, catalog row or abstract that names a flagged or
# MEDIUM claim without its label must fail, and the same slice with the labels
# restored must pass.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-restatement-labels.py"
FIXTURES="$SCRIPT_DIR/../tests/fixtures/restatement-labels"

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
# intended reason rather than for any violation at all.
run() {
  local expected="$1" label="$2" want_err=""
  shift 2
  if [[ "${1:-}" == --err ]]; then
    want_err="$2"
    shift 2
  fi
  local err actual
  python3 "$SUT" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
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

# expect_out <label> <want>: the last run's stdout equals <want>.
expect_out() {
  local out
  out="$(cat "$WORK/stdout")"
  if [[ "$out" == "$2" ]]; then
    pass "$1"
  else
    fail "$1: want '$2', got '$out'"
  fi
}

# claim <id or -> <confidence>; "-" omits the id: key.
claim() {
  printf '  - claim: "c"\n'
  if [[ "$1" != - ]]; then printf '    id: %s\n' "$1"; fi
  printf '    confidence: %s\n    applies_to: version-independent\n    sources: []\n' "$2"
}

# mkslice <name> <claims text> <index body> [sidecar body]; prints the slice dir.
mkslice() {
  local d="$WORK/$1"
  mkdir -p "$d"
  printf -- '---\nabstract: a\n---\n# Index\n\n%s\n' "$3" >"$d/RESEARCH.md"
  printf -- '---\ntopic: t\nsection: s\nabstract: a\nclaims:\n%s\nproduced_by: p\n---\n# Body\n\n%s\n' \
    "$2" "${4:-}" >"$d/RESEARCH-s.md"
  printf '%s' "$d"
}

FLAGGED="$(claim M1 'HIGH (single source)')"
MEDIUM="$(claim CI-02 MEDIUM)"
PLAIN="$(claim K9 HIGH)"

# --- the fixture pair -------------------------------------------------------

run 1 "unlabeled fixture fails" --err 'RESEARCH.md:13: M1 (HIGH (single source)) appears without its label' \
  "$FIXTURES/unlabeled"
for want in 'RESEARCH.md:17: M1 (HIGH (single source))' 'RESEARCH.md:27: CI-02 (MEDIUM)' \
  'RESEARCH.md:33: CI-02 (MEDIUM)' 'RESEARCH-perf.md:4: M1 (HIGH (single source))' \
  'RESEARCH-perf.md:45: M1 (HIGH (single source))'; do
  if [[ "$(cat "$WORK/stderr")" == *"$want appears without its label"* ]]; then
    pass "unlabeled fixture reports $want"
  else
    fail "unlabeled fixture should report $want: $(cat "$WORK/stderr")"
  fi
done
expect_out "unlabeled fixture summary line" 'status=fail violations=6 ids=3 labeled=2 mentions=7'
if [[ "$(cat "$WORK/stderr")" != *K9* && "$(cat "$WORK/stderr")" != *'RESEARCH.md:39:'* ]]; then
  pass "a plain HIGH claim and the fetch log are not reported"
else
  fail "a plain HIGH claim and the fetch log are not reported: $(cat "$WORK/stderr")"
fi
run 0 "corrected fixture passes" "$FIXTURES/corrected"
expect_out "corrected fixture summary line" 'status=pass ids=3 labeled=2 mentions=7'

# --- labels -----------------------------------------------------------------

run 0 "labeled mentions pass" \
  "$(mkslice labeled "$FLAGGED
$MEDIUM" 'See M1 (HIGH (single source)) and CI-02 (MEDIUM).')"
run 1 "a flagged claim's bare pointer fails" --err 'M1 (HIGH (single source)) appears without its label' \
  "$(mkslice bare "$FLAGGED" 'See M1.')"
run 1 "HIGH alone does not carry the single-source label" --err 'M1 (HIGH (single source))' \
  "$(mkslice high-only "$FLAGGED" 'See M1 (HIGH).')"
run 1 "a LOW claim needs its label" --err 'L3 (LOW) appears without its label' \
  "$(mkslice low "$(claim L3 LOW)" 'L3 is below the bar.')"
run 1 "BELOW is not the LOW label" --err 'L3 (LOW)' \
  "$(mkslice below "$(claim L3 LOW)" 'L3 is BELOW the bar.')"
run 0 "a LOW claim with its label passes" "$(mkslice low-ok "$(claim L3 LOW)" 'L3 (LOW) is a gap.')"
run 0 "a plain HIGH claim needs no label" "$(mkslice plain "$PLAIN" 'K9 is settled.')"
run 0 "a claim without an id is not looked for" \
  "$(mkslice no-id "$(claim - MEDIUM)" 'Nothing names it.')"
expect_out "a slice with no ids passes with ids=0" 'status=pass ids=0 labeled=0 mentions=0'

# --- matching ---------------------------------------------------------------

run 0 "M1 is not found in M10" "$(mkslice m10 "$FLAGGED" 'M10 is another claim.')"
run 0 "S2 is not found in S2a" "$(mkslice s2a "$(claim S2 MEDIUM)" 'S2a is another claim.')"
run 1 "a range names both ends" --err 'P3 (MEDIUM)' \
  "$(mkslice range "$(claim P1 HIGH)
$(claim P3 MEDIUM)" 'Causes P1-P3 hold.')"
# mkslice puts the index body on line 6, and a one-claim sidecar's body on
# line 15.
run 1 "a table row is one line" --err 'RESEARCH.md:6: CI-02 (MEDIUM)' \
  "$(mkslice row "$MEDIUM" '| CI-02 | started_at - created_at |')"
run 1 "a sidecar body line is checked" --err 'RESEARCH-s.md:15: M1 (HIGH (single source))' \
  "$(mkslice sidecar-body "$FLAGGED" 'Index.' 'M1 holds.')"
run 0 "the claims block itself is not a restatement" "$(mkslice header-only "$FLAGGED" 'Index.')"
abstract_slice="$(mkslice abstract "$FLAGGED" 'Index.')"
printf -- '---\ntopic: t\nsection: s\nabstract: M1 says so\nclaims:\n%s\nproduced_by: p\n---\n' \
  "$FLAGGED" >"$abstract_slice/RESEARCH-s.md"
run 1 "the sidecar abstract is checked" --err 'RESEARCH-s.md:4: M1' "$abstract_slice"

fetch="$(mkslice fetch "$FLAGGED" '## Fetch log

| Claim | URL |
|---|---|
| M1 | https://example.com |

## Summary

M1 again.')"
run 1 "the fetch log is skipped and the next section is not" --err 'RESEARCH.md:14: M1' "$fetch"
if [[ "$(cat "$WORK/stderr")" != *'RESEARCH.md:10:'* ]]; then
  pass "the fetch log row is not reported"
else
  fail "the fetch log row is not reported: $(cat "$WORK/stderr")"
fi
run 1 "a fetch-log heading inside a code fence does not open a skip" --err 'RESEARCH.md:10: M1' \
  "$(mkslice fenced "$FLAGGED" '```text
## Fetch log
```

See M1.')"

# --- ungradeable ------------------------------------------------------------

run 2 "missing slice" "$WORK/does-not-exist"
no_index="$(mkslice no-index "$FLAGGED" 'x')"
rm "$no_index/RESEARCH.md"
run 2 "no index" --err 'no index' "$no_index"
no_sidecar="$(mkslice no-sidecar "$FLAGGED" 'x')"
mv "$no_sidecar/RESEARCH-s.md" "$no_sidecar/notes.md"
run 2 "no sidecars" --err 'no RESEARCH-*.md sidecar' "$no_sidecar"
run 2 "an id that is not a claim ID" --err 'id is not a claim ID: m1' \
  "$(mkslice bad-id "$(claim m1 MEDIUM)" 'x')"
run 2 "an empty id" --err 'id is not a claim ID: None' \
  "$(mkslice empty-id "$(claim '' MEDIUM)" 'x')"
run 2 "one id declared twice" --err 'id M1 is already declared' \
  "$(mkslice dup-id "$FLAGGED
$(claim M1 MEDIUM)" 'x')"
no_claims_key="$(mkslice no-claims-key "$FLAGGED" 'x')"
printf -- '---\ntopic: t\n---\n' >"$no_claims_key/RESEARCH-s.md"
run 2 "a sidecar without a claims: key" --err 'no claims: key' "$no_claims_key"
run 0 "--help" --help
run 2 "no args"
run 2 "unknown flag" "$FIXTURES/corrected" --strict
run 2 "two slice dirs" "$FIXTURES/corrected" "$FIXTURES/unlabeled"
expect_out "ungradeable summary line" 'status=ungradeable'

# A labeled mention in a sub-slice is never read.
nested="$(mkslice nested "$FLAGGED" 'Index.')"
mkdir -p "$nested/sub"
printf -- '---\nabstract: a\n---\nM1 here.\n' >"$nested/sub/RESEARCH.md"
run 0 "sub-slices are not recursed into" "$nested"

total=$((passes + fails))
if [[ "$fails" -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$total"
  exit 0
fi
printf '\n%d of %d case(s) failed.\n' "$fails" "$total" >&2
exit 1
