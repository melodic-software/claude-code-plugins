#!/usr/bin/env bash
# Black-box contract test for check-claim-eligibility.py.
#
# Self-contained and cwd-independent; mutates only its own guarded mktemp dir.
#
# The cases that matter are the ones a verifier kept failing by hand: a
# single-source flag on a behavior claim or a third-party report (row 4), and
# a HIGH claim whose tier mix is MEDIUM (row 7). Each has a passing twin.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-claim-eligibility.py"

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

expect_out() {
  local out
  out="$(cat "$WORK/stdout")"
  if [[ "$out" == "$2" ]]; then
    pass "$1"
  else
    fail "$1: want '$2', got '$out'"
  fi
}

# src <tier> <pool> [role] [standing]
src() {
  printf '      - url: "https://example.com/%s"\n        tier: %s\n        pool: "%s"\n        role: %s\n        standing: %s\n' \
    "$2" "$1" "$2" "${3:-corroborator}" "${4:-current}"
}

# claim <id> <confidence> <kind or -> <owner or -> <extra key lines> <sources>
# "-" omits that key.
claim() {
  printf '  - claim: "c"\n    id: %s\n    confidence: %s\n' "$1" "$2"
  if [[ "$3" != - ]]; then printf '    claim_kind: %s\n' "$3"; fi
  if [[ "$4" != - ]]; then printf '    source_owner: "%s"\n' "$4"; fi
  if [[ -n "$5" ]]; then printf '%s\n' "$5"; fi
  printf '    sources:\n%s\n' "$6"
}

# mkslice <name> <claims text>; prints the slice dir.
mkslice() {
  local d="$WORK/$1"
  mkdir -p "$d"
  printf -- '---\nabstract: a\n---\n# Index\n' >"$d/RESEARCH.md"
  printf -- '---\ntopic: t\nsection: s\nabstract: a\nclaims:\n%s\nproduced_by: p\n---\n# Body\n' \
    "$2" >"$d/RESEARCH-s.md"
  printf '%s' "$d"
}

THREE="$(src 1 Vendor primary)
$(src 1 'Lab A')
$(src 0 'Own probe')"
REASON='    single_source: "the vendor publishes its own changelog; copies quote it"'

# --- row 7: the tier mix behind HIGH ----------------------------------------

run 0 "HIGH on three current Tier 0/1 pools passes" \
  "$(mkslice high-ok "$(claim H1 HIGH behavior Vendor '' "$THREE")")"
expect_out "pass summary line" 'status=pass claims=1 high=1 flagged=0'
run 1 "2 Tier 1 + 1 Tier 2 at HIGH fails as MEDIUM" --err 'found 2; that mix is MEDIUM' \
  "$(mkslice high-mix "$(claim H2 HIGH behavior Vendor '' "$(src 1 Vendor primary)
$(src 1 'Lab A')
$(src 2 Blog)")")"
expect_out "fail summary line" 'status=fail violations=1 claims=1 high=1 flagged=0'
run 1 "two Tier 1 sources in one pool count once" --err 'found 2' \
  "$(mkslice high-pool "$(claim H3 HIGH behavior Vendor '' "$(src 1 Vendor primary)
$(src 1 vendor)
$(src 1 'Lab A')")")"
run 1 "a historical source does not count toward HIGH" --err 'found 2' \
  "$(mkslice high-hist "$(claim H4 HIGH behavior Vendor '' "$(src 1 Vendor primary)
$(src 1 'Lab A')
$(src 0 'Own probe' corroborator historical)")")"
run 0 "a MEDIUM claim needs no tier mix" \
  "$(mkslice medium "$(claim M1 MEDIUM behavior Vendor '' "$(src 1 Vendor primary)")")"

# --- row 4: single-source flag eligibility ----------------------------------

run 0 "a first-party content claim may carry the flag" \
  "$(mkslice flag-ok "$(claim F1 'HIGH (single source)' content Vendor "$REASON" "$(src 1 Vendor primary)")")"
expect_out "flagged summary line" 'status=pass claims=1 high=0 flagged=1'
run 1 "a behavior claim gets no flag" --err 'a behavior claim gets no flag' \
  "$(mkslice flag-behavior "$(claim F2 'HIGH (single source)' behavior Vendor "$REASON" "$(src 1 Vendor primary)")")"
run 1 "a third-party report is not eligible" --err 'a third-party report is not eligible' \
  "$(mkslice flag-third "$(claim F3 'HIGH (single source)' content ExampleCloud "$REASON" "$(src 1 'Example University' primary)")")"
run 1 "the flag needs a single_source: reason" --err 'needs a single_source: reason' \
  "$(mkslice flag-noreason "$(claim F4 'HIGH (single source)' content Vendor '' "$(src 1 Vendor primary)")")"
run 1 "single_source: on an unflagged claim fails" --err 'single_source: is only for' \
  "$(mkslice reason-high "$(claim F5 HIGH behavior Vendor "$REASON" "$THREE")")"
run 1 "a subject_pool claim is at most MEDIUM" --err 'at most MEDIUM, not HIGH' \
  "$(mkslice subject-high "$(claim S1 HIGH behavior Vendor '    subject_pool: "Vendor"' "$THREE")")"
run 0 "a subject_pool claim at MEDIUM passes" \
  "$(mkslice subject-ok "$(claim S2 MEDIUM behavior Vendor '    subject_pool: "Vendor"' "$(src 1 Vendor primary)")")"

# --- the two declared fields ------------------------------------------------

run 1 "a claim with no claim_kind fails" --err 'claim 1 [K1]: claim_kind is None' \
  "$(mkslice no-kind "$(claim K1 MEDIUM - Vendor '' "$(src 1 Vendor primary)")")"
run 1 "a claim_kind outside content|behavior fails" --err "claim_kind is 'fact'" \
  "$(mkslice bad-kind "$(claim K2 MEDIUM fact Vendor '' "$(src 1 Vendor primary)")")"
run 1 "a claim with no source_owner fails" --err 'source_owner is missing or empty' \
  "$(mkslice no-owner "$(claim K3 MEDIUM content - '' "$(src 1 Vendor primary)")")"
run 1 "an unknown confidence fails" --err "confidence is 'VERY HIGH'" \
  "$(mkslice bad-conf "$(claim K4 'VERY HIGH' content Vendor '' "$(src 1 Vendor primary)")")"
run 0 "claims: [] passes with claims=0" "$(mkslice none '[]')"
printf -- '---\ntopic: t\nsection: s\nabstract: a\nclaims: []\nproduced_by: p\n---\n' >"$WORK/none/RESEARCH-s.md"
run 0 "an empty claims list passes" "$WORK/none"
expect_out "empty summary line" 'status=pass claims=0 high=0 flagged=0'

# --- ungradeable ------------------------------------------------------------

run 2 "missing slice" "$WORK/does-not-exist"
no_index="$(mkslice no-index "$(claim X1 MEDIUM content Vendor '' "$(src 1 Vendor primary)")")"
rm "$no_index/RESEARCH.md"
run 2 "no index" --err 'no index' "$no_index"
no_sidecar="$(mkslice no-sidecar "$(claim X2 MEDIUM content Vendor '' "$(src 1 Vendor primary)")")"
mv "$no_sidecar/RESEARCH-s.md" "$no_sidecar/notes.md"
run 2 "no sidecars" --err 'no RESEARCH-*.md sidecar' "$no_sidecar"
no_claims="$(mkslice no-claims "$(claim X3 MEDIUM content Vendor '' "$(src 1 Vendor primary)")")"
printf -- '---\ntopic: t\n---\n' >"$no_claims/RESEARCH-s.md"
run 2 "a sidecar without a claims: key" --err 'no claims: key' "$no_claims"
run 0 "--help" --help
run 2 "no args"
run 2 "unknown flag" "$WORK/none" --strict
run 2 "two slice dirs" "$WORK/none" "$WORK/none"
expect_out "ungradeable summary line" 'status=ungradeable'

total=$((passes + fails))
if [[ "$fails" -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$total"
  exit 0
fi
printf '\n%d of %d case(s) failed.\n' "$fails" "$total" >&2
exit 1
