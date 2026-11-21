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

# shellcheck source=../lib/test-pass-fail.sh
source "$SCRIPT_DIR/../lib/test-pass-fail.sh"

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
  'Scope check: 2 of 27 questions registered' \
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
  'Context: the threshold rests on Q15, paging on failure.' \
  '➡️ My recommendation: no; the alert threshold stays as it is.'
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
  'Scope check: 2 of 27 questions registered' \
  'Q15: Which layout?' \
  '```text' \
  'C1 C3 Q14 lane' \
  '```' \
  'Discovery: which layouts the readers already know.'
run "a fenced block is ignored" 0 fenced.md 'status=ok'
run "a fenced ledger row is not a code" 0 fenced.md '^codes=6 '

round words.md \
  'Q15: Should lanes share a cache?' \
  'Context: the C10 rule and Q140 are not ledger ids, and planes are not lanes (one builder session each).'
run "a plural term, named later, is still bare at first use" 1 words.md '^bare=1:lane$'
round words2.md \
  'Scope check: 2 of 27 questions registered' \
  'Q15: Should two builder sessions share a cache?' \
  'Context: the C10 rule and Q140 are not ledger ids; planes and a laneway are not the term.' \
  'My recommendation: no; each session keeps its own cache.'
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
round dot-heading.md 'Scope check: 2 of 27 questions registered' 'Q15. Should a failed retry page the on-call?' 'My recommendation: no.'
run "a question opened with Q<N>. names its own id" 0 dot-heading.md 'bare=0 status=ok'
round paren-heading.md '**Q15)** Should a failed retry page the on-call?' 'Q16) Does it follow Q15?'
run "a question opened with Q<N>) names its own id" 1 paren-heading.md '^bare=2:Q15$'
run "only the later bare use of a Q<N>) id fails" 1 paren-heading.md 'bare=1 status=fail'

# A scenario walk numbers its scenarios S1, S2 inside one question. Once an assumption sweep has
# logged `- S<N> |` rows, a bare S<N> is a sweep item, so scenarios are qualified (`Q17.S1:`).
cat >"$TMP/sweep-ledger.md" <<'MD'
## Assumption sweep

- sweep 1 | register through Q14
- S1 | sweep 1 | undecided | decision | Q14 recommendation, retry window | Q15
- S2 | sweep 1 | hidden-default | decision | Q14 recommendation, alert channel | Q16
MD
round walk-overlap.md \
  'Q17: What is a booking once it moves?' \
  'Context:' \
  'S1: Priya holds Tuesday 10:00 and pays 40.00; on Monday she moves it to Thursday.' \
  'Checked against: S1'
out="$(bash "$SUT" --ledger "$TMP/sweep-ledger.md" "$TMP/walk-overlap.md" 2>&1)"
got=$?
if [[ "$got" -eq 1 ]] && grep -q '^bare=3:S1$' <<<"$out" && grep -q 'bare=1 status=fail' <<<"$out"; then
  pass "a scenario opened with a bare S<N>: that is also a sweep id fails"
else
  fail "a scenario opened with a bare S<N>: that is also a sweep id fails ($out)"
fi
round walk-overlap-round.md \
  'Scope check: 2 of 27 questions registered' \
  'Q17: What is a booking once it moves?' \
  'Context:' \
  'S1: Priya holds Tuesday 10:00 and pays 40.00; on Monday she moves it to Thursday.' \
  'Checked against: S1' \
  'My recommendation: the same booking, moved.'
run "with no sweep rows a scenario opened with a bare S<N>: passes" 0 walk-overlap-round.md 'bare=0 status=ok'
round walk.md \
  'Scope check: 2 of 27 questions registered' \
  'Q17: What is a booking once it moves?' \
  'Context:' \
  'Q17.S1: Priya holds Tuesday 10:00 and pays 40.00; on Monday she moves it to Thursday.' \
  '(a) Same booking. (b) A new booking. Recommend (a): forces "reschedule".' \
  '**Q17.S2:** Omar cancels on Wednesday. Recommend (b), Q17.S1 still stands: forces "cancel".' \
  'My recommendation: a moved booking stays the same booking.'
if out="$(bash "$SUT" --ledger "$TMP/sweep-ledger.md" "$TMP/walk.md" 2>&1)" &&
  grep -q 'codes=3 bare=0 status=ok' <<<"$out"; then
  pass "a scenario walk with question-qualified ids passes beside sweep rows"
else
  fail "a scenario walk with question-qualified ids passes beside sweep rows ($out)"
fi
round walk-then-sweep.md \
  'Q17: What is a booking once it moves?' \
  'Q17.S1: Priya holds Tuesday 10:00. Recommend (a): forces "reschedule".' \
  'Checked against: S1'
out="$(bash "$SUT" --ledger "$TMP/sweep-ledger.md" "$TMP/walk-then-sweep.md" 2>&1)"
got=$?
if [[ "$got" -eq 1 ]] && grep -q '^bare=3:S1$' <<<"$out"; then
  pass "a qualified scenario id does not name the sweep's S<N>"
else
  fail "a qualified scenario id does not name the sweep's S<N> ($out)"
fi
round walk-bare.md \
  'Q17: What is a booking once it moves?' \
  'Context: S1 and S2 decide it.'
out="$(bash "$SUT" --ledger "$TMP/sweep-ledger.md" "$TMP/walk-bare.md" 2>&1)"
got=$?
if [[ "$got" -eq 1 ]] && grep -q '^bare=2:S1$' <<<"$out"; then
  pass "a scenario id shown with nothing beside it is bare"
else
  fail "a scenario id shown with nothing beside it is bare ($out)"
fi

cat >"$TMP/problem-ledger.md" <<'MD'
## Problems

- P1 | staff cannot find the queue | agreed

## Open-question register

- Q1 | open | round 1 | Which queue? | problem:: P1
MD
round problem-bare.md \
  'Q2: Does the alert fix it?' \
  'Context: this serves P1 and Q1 (the queue question).'
out="$(bash "$SUT" --ledger "$TMP/problem-ledger.md" "$TMP/problem-bare.md" 2>&1)"
got=$?
if [[ "$got" -eq 1 ]] && grep -q '^bare=2:P1$' <<<"$out" && grep -q 'codes=3 bare=1 status=fail' <<<"$out"; then
  pass "a bare problem id fails"
else
  fail "a bare problem id fails ($out)"
fi
round problem-named.md \
  'Scope check: 2 of 27 questions registered' \
  'Q2: Does the alert fix it?' \
  'Context: this serves P1, staff cannot find the queue, and Q1 (the queue question).' \
  'Withheld: the alert trial has not reported yet.'
if out="$(bash "$SUT" --ledger "$TMP/problem-ledger.md" "$TMP/problem-named.md" 2>&1)" &&
  grep -q 'bare=0 status=ok' <<<"$out"; then
  pass "a named problem id passes"
else
  fail "a named problem id passes ($out)"
fi

cat >"$TMP/fixture-ledger.md" <<'MD'
## Open-question register

- Q4 | answered | round 1 | One write per job? | yes
- Q10 | open | round 3 | Audit a failed retry? |
- Q11 | open | round 3 | Who reads the entries? | kind:: discovery
- Q12 | open | round 3 | Which queue? |
- Q13 | open | round 3 | Which store? |
MD
fixture="$SCRIPT_DIR/../surface/tests/fixtures/round-file/round-full.md"
if out="$(bash "$SUT" --ledger "$TMP/fixture-ledger.md" "$fixture" 2>&1)" &&
  grep -q 'codes=5 bare=0 status=ok' <<<"$out"; then
  pass "the shared round fixture names every code"
else
  fail "the shared round fixture names every code ($out)"
fi
if grep -q 'structure=0' <<<"$out"; then
  pass "the shared round fixture passes the structure checks"
else
  fail "the shared round fixture passes the structure checks ($out)"
fi
awk '{ print } /^- No reader is named yet\.$/ {
  print "- Basis: no reader survey exists yet."
  print "- My recommendation: none until a reader is named."
}' "$fixture" >"$TMP/fixture-bullets.md"
out="$(bash "$SUT" --ledger "$TMP/fixture-ledger.md" "$TMP/fixture-bullets.md" 2>&1)"
got=$?
if [[ "$got" -eq 0 ]] && grep -q 'bare=0 status=ok structure=0' <<<"$out"; then
  pass "a Context bullet that starts with a label word is not a label"
else
  fail "a Context bullet that starts with a label word is not a label (exit $got: $out)"
fi

round no-rec.md \
  'Scope check: 2 of 27 questions registered' \
  '' \
  '❓ Q15: **Should a failed retry page the on-call?**' \
  'Context: each retry runs alone.'
run "a decision question with no recommendation fails" 1 no-rec.md '^missing=3:recommendation$'
run "a missing recommendation fails the summary" 1 no-rec.md 'bare=0 status=fail structure=1'
round discovery.md \
  'Scope check: 2 of 27 questions registered' \
  '' \
  '❓ Q15: **Who reads the retry entries?**' \
  'Context: no reader is named yet.' \
  'Discovery: who reads them settles whether they need a dashboard.'
run "a discovery question with a Discovery: line passes" 0 discovery.md 'bare=0 status=ok structure=0'
round no-scope.md \
  'Round 2. The retry budget is settled.' \
  '' \
  '❓ Q15: **Should a failed retry page the on-call?**' \
  '➡️ **My recommendation:** no; a retry stays silent.'
run "a header with no Scope check: line fails" 1 no-scope.md '^missing=1:scope-check$'
run "a bold recommendation label after a marker counts" 1 no-scope.md 'structure=1$'
round two-recs.md \
  'Scope check: 2 of 27 questions registered' \
  'Q15: Should a failed retry page the on-call?' \
  'My recommendation: no.' \
  'Withheld: the paging trial has not reported.'
run "a question with two answer lines fails" 1 two-recs.md '^missing=2:single-recommendation$'
round product.md \
  'Scope check: 3 of 15 questions registered' \
  '' \
  'Q3: Who has this problem today, by name?' \
  'Strong answer: one named person, their role, and the last time it cost them.' \
  'Basis: reference/product-principles.md, principle 4 (a real person with the problem)'
run "a product-action round with a Strong answer: line passes" 0 product.md 'bare=0 status=ok structure=0'

if [[ "$fails" -gt 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
