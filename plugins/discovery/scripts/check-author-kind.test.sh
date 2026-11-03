#!/usr/bin/env bash
# Black-box contract test for check-author-kind.py.
#
# Self-contained and cwd-independent; mutates only its own guarded mktemp dir.
#
# The case that matters is the one a verifier kept failing by hand: a Direct
# claim resting only on a comment an agent wrote under a person's login.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-author-kind.py"

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

# src <author_kind or ->; "-" omits the key.
src() {
  printf '      - ref: "PR #1"\n        kind: source-control\n        reliability: "the change author, two years old"\n'
  if [[ "$1" != - ]]; then printf '        author_kind: %s\n' "$1"; fi
}

# claim <tier or -> <sources text>; "-" omits the tier.
claim() {
  printf '  - claim: "c"\n'
  if [[ "$1" != - ]]; then printf '    tier: %s\n' "$1"; fi
  printf '    sources:\n%s\n' "$2"
}

# mkslice <name> <claims text>; prints the slice dir.
mkslice() {
  local d="$WORK/$1"
  mkdir -p "$d"
  printf '# Why\n\nRun status: complete\n' >"$d/INTENT.md"
  printf -- '---\ntopic: t\nsection: s\nabstract: a\nquestion: q\nclaims:\n%s\nproduced_by: p\n---\n# Body\n' \
    "$2" >"$d/INTENT-s.md"
  printf '%s' "$d"
}

QUOTE="$(src owner-quote)"
RELAY="$(src agent-relay)"

# --- a Direct claim needs a person's own words ------------------------------

run 1 "Direct with only an agent relay fails" --err 'claim 1: Direct needs an owner-quote source' \
  "$(mkslice relay "$(claim Direct "$RELAY")")"
expect_out "fail summary line" 'status=fail violations=1 claims=1 direct=1'
run 1 "Direct with two agent relays fails" --err 'Direct needs an owner-quote source' \
  "$(mkslice relays "$(claim Direct "$RELAY
$RELAY")")"
run 0 "Direct with an owner quote passes" \
  "$(mkslice quote "$(claim Direct "$QUOTE")")"
expect_out "pass summary line" 'status=pass claims=1 direct=1'
run 0 "Direct with an owner quote and a relay passes" \
  "$(mkslice both "$(claim Direct "$RELAY
$QUOTE")")"
run 1 "Direct with no sources fails" --err 'Direct needs an owner-quote source' \
  "$(mkslice empty "$(claim Direct '')")"
run 0 "a trailing comment on the tier and the tag is read past" \
  "$(mkslice comments "$(claim 'Direct   # a comment' "$(src 'owner-quote  # the quoted span')")")"

# --- a source on a Direct claim needs a valid tag ---------------------------

run 1 "a missing author_kind on a Direct source fails" --err 'source 1: author_kind is None' \
  "$(mkslice no-tag "$(claim Direct "$(src -)")")"
run 1 "an invalid author_kind on a Direct source fails" --err "author_kind is 'person'" \
  "$(mkslice bad-tag "$(claim Direct "$(src person)")")"
run 1 "a missing tag beside an owner quote still fails" --err 'source 2: author_kind is None' \
  "$(mkslice mixed-tag "$(claim Direct "$QUOTE
$(src -)")")"

# --- other tiers are not gated ----------------------------------------------

for tier in Supported Inferred Speculative Unknown; do
  run 0 "$tier with only a relay passes" \
    "$(mkslice "relay-$tier" "$(claim "$tier" "$RELAY")")"
done
expect_out "a non-Direct claim counts in claims only" 'status=pass claims=1 direct=0'
run 0 "an Unknown claim's searched sources carry no tag" \
  "$(mkslice unknown-untagged "$(claim Unknown "$(src -)")")"

# --- a tier the check cannot read does not slip past it ---------------------

run 1 "a missing tier fails" --err 'claim 1: tier is None' \
  "$(mkslice no-tier "$(claim - "$RELAY")")"
run 1 "a lowercase direct fails rather than skipping the rule" --err "tier is 'direct'" \
  "$(mkslice low-tier "$(claim direct "$RELAY")")"

# --- counting across claims and sidecars ------------------------------------

two="$(mkslice two "$(claim Direct "$QUOTE")
$(claim Inferred "$RELAY")")"
run 0 "two claims, one Direct" "$two"
expect_out "two-claim summary line" 'status=pass claims=2 direct=1'
printf -- '---\ntopic: t\nsection: b\nabstract: a\nquestion: q\nclaims:\n%s\nproduced_by: p\n---\n' \
  "$(claim Direct "$RELAY")" >"$two/INTENT-b.md"
run 1 "a violation names its own sidecar" --err 'INTENT-b.md: claim 1' "$two"
expect_out "second sidecar counts" 'status=fail violations=1 claims=3 direct=2'

# --- ungradeable ------------------------------------------------------------

mkslice none '[]' >/dev/null
printf -- '---\ntopic: t\nclaims: []\nproduced_by: p\n---\n' >"$WORK/none/INTENT-s.md"
run 0 "claims: [] passes" "$WORK/none"
expect_out "empty summary line" 'status=pass claims=0 direct=0'
run 2 "missing slice" "$WORK/does-not-exist"
no_index="$(mkslice no-index "$(claim Direct "$QUOTE")")"
rm "$no_index/INTENT.md"
run 2 "no index" --err 'no index' "$no_index"
no_sidecar="$(mkslice no-sidecar "$(claim Direct "$QUOTE")")"
mv "$no_sidecar/INTENT-s.md" "$no_sidecar/notes.md"
run 2 "no sidecars" --err 'no INTENT-*.md sidecar' "$no_sidecar"
no_claims="$(mkslice no-claims "$(claim Direct "$QUOTE")")"
printf -- '---\ntopic: t\n---\n' >"$no_claims/INTENT-s.md"
run 2 "a sidecar without a claims: key" --err 'no claims: key' "$no_claims"
no_header="$(mkslice no-header "$(claim Direct "$QUOTE")")"
printf '# Body\n' >"$no_header/INTENT-s.md"
run 2 "a sidecar without front matter" --err 'no front matter' "$no_header"
run 2 "a source that does not open with ref: names ref:" --err 'does not start with ref:' \
  "$(mkslice bad-source "$(claim Direct '      - kind: source-control')")"
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
