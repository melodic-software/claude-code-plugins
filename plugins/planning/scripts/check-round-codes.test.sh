#!/usr/bin/env bash
# Black-box contract test for check-round-codes.sh.
#
# Self-contained and cwd-independent; writes its fixtures in its own mktemp dir
# and mutates nothing else.
#
# SC2016 is disabled file-wide on purpose: the single-quoted backtick spans are literal
# fixture text, not expansions.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-round-codes.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/ledger.md" <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | V1 ships without SSO | user, round 1
- C3 | confirmed | scoped change only | user, round 1

## Open-question register

- Q14 | answered | round 1 | What is the retry budget? | three tries

```text
- Q99 | open | round 1 | fenced example |
```

**Session shorthand:**
- lane: one parallel builder session working an isolated slice

## Self-answered facts

- F1 | answered-from-codebase | Which queue? | BullMQ 5 | package.json:14
MD

# round <file> <line>...: a round whose body is the given lines.
round() {
  local file="$TMP/$1"
  shift
  printf '%s\n' "$@" >"$file"
}

# run <label> <want_exit> <round file> <pattern>
run() {
  local label="$1" want="$2" file="$TMP/$3" pattern="$4" out got
  out="$(bash "$SUT" --ledger "$TMP/ledger.md" "$file" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label (want exit $want, got $got)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  if [[ -n "$pattern" ]] && ! grep -qE -- "$pattern" <<<"$out"; then
    fail "$label (exit $got as wanted, but no /$pattern/ in output)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  pass "$label"
}

round named.md \
  'Round 2. The retry budget (question Q14, retry budget) is three tries.' \
  '' \
  '❓ Q15: **Should a failed retry page the on-call?**' \
  'Context: each lane (one parallel builder session) retries alone (`src/retry.ts:12`).' \
  'This stays a scoped change (C3), and V1 has no SSO.' \
  '➡️ My recommendation: no; a lane retries silently.' \
  'Basis: verified, `src/retry.ts:12`.' \
  'Checked against: C1: V1 ships without SSO; C3 (scoped change only).' \
  'Alternatives:' \
  '- (a) Page on every failure. Fast response, but noisy nights.' \
  '' \
  'Q16: Does question Q15, paging on failure, change the alert threshold?' \
  'Context: the threshold rests on Q15, paging on failure.'
run "a round that names every code passes" 0 named.md 'bare=0 status=ok'

round bare.md \
  'Q15: Should a failed retry page the on-call?' \
  'Context: this follows Q14 and each lane retries alone.' \
  'Checked against: C1, C3'
run "a bare ledger id fails" 1 bare.md '^bare=2:Q14$'
run "a bare shorthand term fails" 1 bare.md '^bare=2:lane$'
run "a code beside another code is bare" 1 bare.md '^bare=3:C1$'
run "the last code in a list is bare" 1 bare.md '^bare=3:C3$'
run "the summary counts each bare code" 1 bare.md 'bare=4 status=fail'

round blocks.md \
  'Q15: Retry budget, C3 (scoped change), applies here?' \
  'Context: C3 again is fine in the same block.' \
  'Q16: Does the same hold?' \
  'Context: C3 holds here too.'
run "each question block names a code on its own" 1 blocks.md '^bare=4:C3$'

round own-ids.md \
  'Q20: Which store?' \
  'Q21: Does it follow Q20?'
run "a question id from the round itself is checked" 1 own-ids.md '^bare=2:Q20$'

round fenced.md \
  'Q15: Which layout?' \
  '```text' \
  'C1 C3 Q14 lane' \
  '```'
run "a fenced block is ignored" 0 fenced.md 'status=ok'
run "a fenced ledger row is not a code" 0 fenced.md '^codes=6 '

round words.md \
  'Q15: Should lanes share a cache?' \
  'Context: the C10 rule and Q140 are not ledger ids, and planes are not lanes (one builder session each).'
run "a plural term, named later, is still bare at first use" 1 words.md '^bare=1:lane$'
round words2.md \
  'Q15: Should two builder sessions share a cache?' \
  'Context: the C10 rule and Q140 are not ledger ids; planes and a laneway are not the term.'
run "a longer token or word is not a code" 0 words2.md 'status=ok'

round open.md 'Q15: Which?' '```'
run "an unterminated fence exits 2" 2 open.md 'unterminated'
run "a missing round file exits 2" 2 nope.md 'not a file'

out="$(bash "$SUT" --ledger "$TMP/ledger.md" 2>&1)"
got=$?
if [[ "$got" -eq 2 ]]; then
  pass "no round file is a usage error"
else
  fail "no round file is a usage error (exit $got: $out)"
fi
round connective.md 'Q15: Which store?' 'Context: this follows Q14, so the budget is fixed.'
run "a comma and a connective do not name a code" 1 connective.md '^bare=2:Q14$'
round words3.md 'Q15: Does Q14 hold?'
run "a code inside the question line is bare" 1 words3.md '^bare=1:Q14$'

if [[ "$fails" -gt 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
