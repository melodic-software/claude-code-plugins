#!/usr/bin/env bash
# The single-quoted backtick spans are literal fixture text, not expansions.
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

round() {
  local file="$TMP/$1"
  shift
  printf '%s\n' "$@" >"$file"
}

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
  '➡️ My recommendation: no; the alert threshold stays as it is (verified, src/retry.ts:12).'
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
  'My recommendation: no; each session keeps its own cache (verified, src/retry.ts:12).'
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
round dot-heading.md 'Scope check: 2 of 27 questions registered' 'Q15. Should a failed retry page the on-call?' 'My recommendation: no (verified, src/retry.ts:12).'
run "a question opened with Q<N>. names its own id" 0 dot-heading.md 'bare=0 status=ok'
round paren-heading.md '**Q15)** Should a failed retry page the on-call?' 'Q16) Does it follow Q15?'
run "a question opened with Q<N>) names its own id" 1 paren-heading.md '^bare=2:Q15$'
run "only the later bare use of a Q<N>) id fails" 1 paren-heading.md 'bare=1 status=fail'

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
  'My recommendation: the same booking, moved (verified, user, round 1).'
run "with no sweep rows a scenario opened with a bare S<N>: passes" 0 walk-overlap-round.md 'bare=0 status=ok'
round walk.md \
  'Scope check: 2 of 27 questions registered' \
  'Q17: What is a booking once it moves?' \
  'Context:' \
  'Q17.S1: Priya holds Tuesday 10:00 and pays 40.00; on Monday she moves it to Thursday.' \
  '(a) Same booking. (b) A new booking. Recommend (a): forces "reschedule".' \
  'Q17.S2: Omar cancels on Wednesday. Recommend (b), Q17.S1 still stands: forces "cancel".' \
  'My recommendation: a moved booking stays the same booking (verified, user, round 1).'
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
out="$(bash "$SUT" --ledger "$TMP/fixture-ledger.md" "$fixture" 2>&1)"
if grep -q 'codes=5 bare=0 ' <<<"$out"; then
  pass "the shared round fixture names every code"
else
  fail "the shared round fixture names every code ($out)"
fi
if grep -q '^extra=4:header$' <<<"$out" && grep -q '^emphasis=1$' <<<"$out" && grep -q 'structure=2$' <<<"$out"; then
  pass "the shared round fixture's retired Held: line and bold round title are its only structure failures"
else
  fail "the shared round fixture's retired Held: line and bold round title are its only structure failures ($out)"
fi
awk '{ print } /^- No reader is named yet\.$/ {
  print "- Basis: no reader survey exists yet."
  print "- My recommendation: none until a reader is named."
}' "$fixture" >"$TMP/fixture-bullets.md"
out="$(bash "$SUT" --ledger "$TMP/fixture-ledger.md" "$TMP/fixture-bullets.md" 2>&1)"
got=$?
if [[ "$got" -eq 1 ]] && grep -q 'bare=0 status=fail structure=2$' <<<"$out" && ! grep -q 'recommendation$' <<<"$out"; then
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
  '➡️ **My recommendation:** no; a retry stays silent (verified, src/retry.ts:12).'
run "a header with no Scope check: line fails" 1 no-scope.md '^missing=1:scope-check$'
run "a bold recommendation label after a marker counts" 1 no-scope.md 'structure=1$'
round two-recs.md \
  'Scope check: 2 of 27 questions registered' \
  'Q15: Should a failed retry page the on-call?' \
  'My recommendation: no.' \
  'Withheld: the paging trial has not reported.'
run "a question with two answer lines fails" 1 two-recs.md '^missing=2:single-recommendation$'
round q-bullet.md \
  'Scope check: 2 of 27 questions registered' \
  '' \
  '❓ Q15: **Should a failed retry page the on-call?**' \
  'Context:' \
  '- Q14: you set the retry budget at three tries.' \
  '1. Q14: the same answer, in a numbered list.' \
  '➡️ My recommendation: no; a retry stays silent.'
run "a list item that opens with Q<N>: is not a question line" 0 q-bullet.md 'bare=0 status=ok structure=0'
round two-scopes.md \
  'Scope check: 2 of 27 questions registered' \
  'Scope check: 3 of 27 questions registered' \
  'Q15: Should a failed retry page the on-call?' \
  'My recommendation: no.'
run "a header with two Scope check: lines fails" 1 two-scopes.md '^missing=1:single-scope-check$'
round product.md \
  'Scope check: 3 of 15 questions registered' \
  '' \
  'Q3: Who has this problem today, by name?' \
  'Strong answer: one named person, their role, and the last time it cost them.' \
  'Basis: reference/product-principles.md, principle 4 (a real person with the problem)'
run "a product-action round with a Strong answer: line passes" 0 product.md 'bare=0 status=ok structure=0'

runx() {
  local label="$1" want="$2" ledger="$TMP/$3" file="$TMP/$4" pattern="$5" out got
  shift 5
  out="$(bash "$SUT" --ledger "$ledger" "$@" "$file" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]] || { [[ -n "$pattern" ]] && ! grep -qE -- "$pattern" <<<"$out"; }; then
    fail "$label (want exit $want and /$pattern/, got exit $got)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  pass "$label"
}
nox() {
  local label="$1" ledger="$TMP/$2" file="$TMP/$3" pattern="$4" out
  shift 4
  out="$(bash "$SUT" --ledger "$ledger" "$@" "$file" 2>&1)"
  if grep -qE -- "$pattern" <<<"$out"; then
    fail "$label (/$pattern/ printed)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  pass "$label"
}

round single-preamble.md \
  "Of the five open decisions, I'm starting with what happens to an event after its last failed attempt." \
  '### Round 2' \
  '' \
  'Scope check: 4 of 27 questions registered' \
  '' \
  '❓ Q4: **After the last failed attempt, should the sender keep the event?**' \
  'Context:' \
  '- Webhooks are delivered at least once (user, round 1).' \
  '➡️ My recommendation: **Yes: keep it.** Dropping breaks at-least-once delivery (verified, user, round 1).'
runx "under single pacing a header line that previews the frontier fails" 1 ledger.md single-preamble.md '^extra=1:single-header$' --pacing single
runx "under round pacing the same header note passes" 0 ledger.md single-preamble.md 'bare=0 status=ok structure=0'
round single-header.md \
  '## Round 2, one question at a time' \
  'Scope check: 4 of 27 questions registered' \
  'Wayfind: the last two rounds each opened more questions than they settled; /planning:wayfind chart can map what is left.' \
  'Open: the alert threshold, waiting on the principle map' \
  'Next round (over the cap of 4): the log format' \
  'Later: replay controls' \
  '---' \
  '' \
  '❓ Q4: **After the last failed attempt, should the sender keep the event?**' \
  'Context:' \
  '- Webhooks are delivered at least once (user, round 1).' \
  '➡️ My recommendation: **Yes: keep it.** Dropping breaks at-least-once delivery (verified, user, round 1).'
runx "under single pacing the prescribed header lines pass" 0 ledger.md single-header.md 'structure=0$' --pacing single
runx "single pacing prints its self-check at line 1" 0 ledger.md single-header.md '^check=1:single-pacing$' --pacing single
nox "round pacing prints no single-pacing self-check" ledger.md single-header.md 'single-pacing'
Q4_BLOCK=(
  '❓ Q4: **After the last failed attempt, should the sender keep the event?**'
  'Context:'
  '- Webhooks are delivered at least once (user, round 1).'
  '➡️ My recommendation: **Yes: keep it.** Dropping breaks at-least-once delivery (verified, user, round 1).'
)
TERM_LINE='Term: retry budget, the tries a delivery gets before it stops (user, round 1). Confirm or correct it.'
SCOPE_LINE='Scope check: 4 of 27 questions registered'
round single-term.md "$TERM_LINE" '### Round 2' '' "$SCOPE_LINE" '' "${Q4_BLOCK[@]}"
runx "under single pacing a Term: line above the title passes" 0 ledger.md single-term.md 'structure=0$' --pacing single
round single-restate.md '### Round 2' 'The retry budget is three tries.' "$SCOPE_LINE" '' "${Q4_BLOCK[@]}"
runx "under single pacing one restate line directly after the title passes" 0 ledger.md single-restate.md 'structure=0$' --pacing single
round single-restate-gap.md '### Round 2' '' 'The retry budget is three tries.' '' "$TERM_LINE" "$SCOPE_LINE" '' "${Q4_BLOCK[@]}"
runx "under single pacing a restate after a blank line, then a Term: line, passes" 0 ledger.md single-restate-gap.md 'structure=0$' --pacing single
round single-two-lines.md '### Round 2' 'The retry budget is three tries.' 'Next comes the dead-letter queue.' "$SCOPE_LINE" '' "${Q4_BLOCK[@]}"
runx "under single pacing a second plain line after the restate fails" 1 ledger.md single-two-lines.md '^extra=3:single-header$' --pacing single
round single-late-line.md '### Round 2' "$SCOPE_LINE" 'The retry budget is three tries.' '' "${Q4_BLOCK[@]}"
runx "under single pacing a plain line after the Scope check: line fails" 1 ledger.md single-late-line.md '^extra=3:single-header$' --pacing single
round single-later-paren.md '### Round 2' "$SCOPE_LINE" 'Later (after this round): replay controls' '' "${Q4_BLOCK[@]}"
runx "under single pacing a parenthesized Later line fails" 1 ledger.md single-later-paren.md '^extra=3:single-header$' --pacing single
round single-term-paren.md '### Round 2' "$SCOPE_LINE" 'Term (agreed): retry budget, the tries a delivery gets before it stops' '' "${Q4_BLOCK[@]}"
runx "under single pacing a parenthesized Term line fails" 1 ledger.md single-term-paren.md '^extra=3:single-header$' --pacing single
round single-scope-paren.md '### Round 2' "$SCOPE_LINE" 'Scope check (draft): 5 of 27 questions registered' '' "${Q4_BLOCK[@]}"
runx "under single pacing a second, parenthesized Scope check line fails" 1 ledger.md single-scope-paren.md '^extra=3:single-header$' --pacing single
out="$(bash "$SUT" --ledger "$TMP/ledger.md" --pacing sometimes "$TMP/single-header.md" 2>&1)"
got=$?
if [[ "$got" -eq 2 ]]; then
  pass "an unknown pacing value is a usage error"
else
  fail "an unknown pacing value is a usage error (exit $got: $out)"
fi

cat >"$TMP/term-ledger.md" <<'MD'
## Open-question register

- Q1 | open | round 2 | Agree the two upstream terms? |
- Q2 | open | round 2 | Add a cluster step? |

## Terminology matrix

| Term | Definition | Source | Status |
|---|---|---|---|
| cluster step | the step that attaches a report to the open cluster with the same dedupe fingerprint | vendor/upstream-triage/README.md:8-10 | proposed |
| `dedupe fingerprint` | a SHA-1 of the normalized first error line | vendor/upstream-triage/README.md:7 | proposed |
MD
round term-elsewhere.md \
  'Scope check: 2 of 27 questions registered' \
  'Q1: **Do these two upstream terms mean what you mean by them?**' \
  'Context:' \
  '- cluster step: the step that attaches a report to the open cluster with the same dedupe fingerprint (vendor/upstream-triage/README.md:8-10).' \
  'My recommendation: agree to both as written.' \
  '---' \
  'Q2: **Should triage gain a cluster step?**' \
  'Context:' \
  '- Upstream keeps a fingerprint-to-issue map (vendor/upstream-triage/README.md:8-10).' \
  'My recommendation: yes, add the cluster step.'
runx "a matrix term used where only another question's Context defines it fails" 1 term-ledger.md term-elsewhere.md '^undefined=7:cluster step$'
runx "the undefined term counts in the structure total" 1 term-ledger.md term-elsewhere.md 'structure=1$'
round term-own.md \
  'Scope check: 2 of 27 questions registered' \
  'Q1: **Do these two upstream terms mean what you mean by them?**' \
  'Context:' \
  '- cluster step: the step that attaches a report to the open cluster with the same dedupe fingerprint (vendor/upstream-triage/README.md:8-10).' \
  'My recommendation: agree to both as written.' \
  '---' \
  'Q2: **Should triage gain cluster steps?**' \
  "Context: Upstream's cluster step attaches a report to the open cluster with the same dedupe fingerprint (vendor/upstream-triage/README.md:8-10)." \
  'My recommendation: yes, add the cluster step.'
runx "a matrix term each question's own Context mentions passes" 0 term-ledger.md term-own.md 'bare=0 status=ok structure=0'
runx "a question after the first prints its own-context-terms self-check" 0 term-ledger.md term-own.md '^check=7:own-context-terms$'
nox "the first question prints no own-context-terms self-check" term-ledger.md term-own.md '^check=2:own-context-terms$'

round judged.md \
  'Scope check: 2 of 27 questions registered' \
  '❓ Q9: **Should the limiter fail open when its store is down?**' \
  'Context:' \
  '- The limiter keeps its counts in the session Redis (src/limit.ts:4).' \
  '➡️ My recommendation: **Yes: fail open.** A short over-admit beats refusing all traffic (verified, src/limit.ts:4).' \
  'Flips if: a burst during a limiter outage hurts more than briefly over-admitting does'
runx "a Flips if: line prints its flips-if-fact self-check" 0 term-ledger.md judged.md '^check=6:flips-if-fact$'
runx "a recommendation prints its existing-control self-check" 0 term-ledger.md judged.md '^check=5:existing-control$'
runx "self-checks leave a clean round passing" 0 term-ledger.md judged.md 'bare=0 status=ok structure=0$'

cat >"$TMP/new-ledger.md" <<'MD'
## Open-question register

- Q4 | answered | round 1 | One write per job? | yes
- Q14 | open | round 4 | Audit a failed retry? |
- Q15 | open | round 4 | Who reads the entries? | kind:: discovery
MD
new_fixture="$SCRIPT_DIR/../surface/tests/fixtures/round-file/round-new.md"
out="$(bash "$SUT" --ledger "$TMP/new-ledger.md" "$new_fixture" 2>&1)"
got=$?
if [[ "$got" -eq 0 ]] && grep -q 'codes=3 bare=0 status=ok structure=0$' <<<"$out" && ! grep -q '^emphasis=' <<<"$out"; then
  pass "the new-layout round fixture passes every check"
else
  fail "the new-layout round fixture passes every check (exit $got: $out)"
fi
round topic.md \
  'Scope check: 2 questions asked so far' \
  '' \
  '❓ Q15 (paging): **Should a failed retry page the on-call?**' \
  '➡️ My recommendation: **no** (verified, src/retry.ts:12)' \
  '' \
  '❓ Q16 (alerts): **Does the alert threshold change?**' \
  'Context:' \
  '1. It rests on Q15 today' \
  '➡️ My recommendation: **no** (verified, src/retry.ts:12)'
run "a Q<N> (<topic>): title opens a question" 1 topic.md '^bare=8:Q15$'
run "each Q<N> (<topic>): question holds its own answer line" 1 topic.md 'bare=1 status=fail structure=0$'
round discovery-pair.md \
  'Scope check: 1 questions asked so far' \
  '' \
  '❓ Q15 (readers): **Who reads the retry entries?**' \
  '' \
  'No recommendation: no reader is named, so any answer would be a guess.' \
  'Your answer settles: whether the entries need a dashboard.'
run "No recommendation: then Your answer settles: passes" 0 discovery-pair.md 'bare=0 status=ok structure=0$'
round discovery-alone.md \
  'Scope check: 1 questions asked so far' \
  '' \
  '❓ Q15 (readers): **Who reads the retry entries?**' \
  'No recommendation: no reader is named, so any answer would be a guess.'
run "No recommendation: with no Your answer settles: fails" 1 discovery-alone.md '^missing=4:answer-settles$'
round discovery-settles-first.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q15 (readers): **Who reads the retry entries?**' \
  'Your answer settles: whether the entries need a dashboard.' \
  'No recommendation: no reader is named, so any answer would be a guess.'
run "Your answer settles: must follow No recommendation:" 1 discovery-settles-first.md '^missing=4:answer-settles$'
round discovery-and-rec.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q15 (readers): **Who reads the retry entries?**' \
  'No recommendation: no reader is named.' \
  'Your answer settles: whether the entries need a dashboard.' \
  '➡️ My recommendation: **a dashboard**'
run "No recommendation: counts as the question's one answer line" 1 discovery-and-rec.md '^missing=2:single-recommendation$'

round three-questions.md \
  'Scope check: 3 questions asked so far' \
  '❓ Q15 (a): **One?**' 'My recommendation: **yes** (verified, src/retry.ts:12)' \
  '❓ Q16 (b): **Two?**' 'My recommendation: **yes** (verified, src/retry.ts:12)' \
  '❓ Q17 (c): **Three?**' 'My recommendation: **yes** (verified, src/retry.ts:12)'
runx "a round over --cap fails with its question count" 1 ledger.md three-questions.md '^over-cap=3$' --cap 2
runx "an over-cap round counts in the structure total" 1 ledger.md three-questions.md 'structure=1$' --cap 2
runx "a round at --cap passes" 0 ledger.md three-questions.md 'structure=0$' --cap 3
nox "a round at --cap prints no over-cap line" ledger.md three-questions.md 'over-cap' --cap 3
for bad in 0 x; do
  runx "--cap $bad is a usage error" 2 ledger.md three-questions.md 'cap' --cap "$bad"
done

round emphasis.md \
  'Scope check: 1 questions asked so far' \
  '' \
  '❓ Q15 (style): **Which store holds the entries?**' \
  '' \
  'Context:' \
  '1. The store is **shared** today (src/store.ts:4)' \
  '2. It is *slow* under load (ops notes)' \
  '3. The _old_ store is gone (ops notes)' \
  '4. The ~~queue~~ is not involved (ops notes)' \
  '5. The `__init__` and `*glob*` literals are code (src/store.ts:9)' \
  '6. A wildcard like a * b * c is arithmetic (ops notes)' \
  '' \
  '➡️ My recommendation: **the shared store**'
for line in 6 7 8 9; do
  runx "emphasis outside the title and the answer line prints emphasis=$line" 1 ledger.md emphasis.md "^emphasis=$line\$"
done
nox "bold on the title and the answer line is not emphasis" ledger.md emphasis.md '^emphasis=(3|13)$'
nox "markup inside inline code and a spaced asterisk are not emphasis" ledger.md emphasis.md '^emphasis=1[01]$'
runx "each emphasis line counts in the structure total" 1 ledger.md emphasis.md 'bare=0 status=fail structure=4$'

round citation-paths.md \
  'Scope check: 1 questions asked so far' \
  '' \
  '❓ Q15 (style): **Which store holds the entries?**' \
  '' \
  'Context:' \
  '1. The package exports the app factory (src/app/__init__.py:12)' \
  '2. CI runs the suite (.github/**/ci.yml:4)' \
  '' \
  'Source: [Store guide, Sharing](https://example.com/guide#sharing)' \
  '> The store is **shared** by _every_ tenant.' \
  'That text makes sharing a question.' \
  '' \
  '➡️ My recommendation: **the shared store**' \
  'Basis: verified, src/app/__main__.py:3'
runx "citation paths with __ or ** and a quoted source line are not emphasis" 0 ledger.md citation-paths.md 'structure=0$'
nox "a citation path or a quote line prints no emphasis line" ledger.md citation-paths.md '^emphasis='

round bullet-flips.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q15 (store): **Which store?**' \
  '➡️ My recommendation: **the shared store** (verified, src/store.ts:4)' \
  '- Why: it already holds the jobs.' \
  '- Flips if: the shared store starts dropping writes.'
runx "a - Flips if: bullet prints its flips-if-fact self-check" 0 ledger.md bullet-flips.md '^check=5:flips-if-fact$'

round retired-header.md \
  'Round 3' \
  'Scope check: 9 questions asked so far' \
  'Held: Q12 (queue choice) until the queue lookup returns' \
  'Settled by evidence: the log format, JSON lines' \
  'Open: the queue choice, waiting on the queue lookup' \
  '' \
  '❓ Q15 (store): **Which store?**' \
  '➡️ My recommendation: **the shared store** (verified, src/store.ts:4)'
run "under round pacing a Held: header line is extra" 1 retired-header.md '^extra=3:header$'
run "under round pacing a Settled by evidence: header line is extra" 1 retired-header.md '^extra=4:header$'
run "the retired header lines are the only structure failures" 1 retired-header.md 'structure=2$'
round single-held.md '### Round 2' 'Held: Q6 (alert threshold), waiting on the principle map' "$SCOPE_LINE" '' "${Q4_BLOCK[@]}"
runx "under single pacing a Held: line right after the title is extra" 1 ledger.md single-held.md '^extra=2:single-header$' --pacing single

EVALS_DIR="$SCRIPT_DIR/../evals"

extract_sample() {
  python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
sys.stdout.write(data[sys.argv[2]][int(sys.argv[3])]["answer"])
' "$1" "$2" "$3"
}

cat >"$TMP/empty-ledger.md" <<'MD'
# /planning:interview Checklist

## Open-question register
MD

cat >"$TMP/single-frontier-ledger.md" <<'MD'
# /planning:interview Checklist

## Open-question register

- Q4 | open | round 2 | What happens to an event after its last failed attempt? |
- Q5 | open | round 2 | How many delivery attempts does the sender make before giving up? |
- Q6 | open | round 2 | What is the delay between attempts? |
- Q7 | open | round 2 | Who is alerted when deliveries to one endpoint keep failing? |
- Q8 | open | round 2 | What does an alert message include? |
MD

SINGLE_SAMPLES="$EVALS_DIR/interview-single-pacing-one-question/samples/one-question-full-layout.json"
extract_sample "$SINGLE_SAMPLES" pass 0 >"$TMP/single-pass-0.md"
extract_sample "$SINGLE_SAMPLES" pass 1 >"$TMP/single-pass-1.md"
extract_sample "$SINGLE_SAMPLES" pass 2 >"$TMP/single-pass-2-full.md"
awk '/^Round 2$/ { p = 1 } p { print }' "$TMP/single-pass-2-full.md" >"$TMP/single-pass-2.md"
extract_sample "$SINGLE_SAMPLES" fail 0 >"$TMP/single-fail-0.md"
extract_sample "$SINGLE_SAMPLES" fail 1 >"$TMP/single-fail-1.md"
extract_sample "$SINGLE_SAMPLES" fail 2 >"$TMP/single-fail-2.md"

runx "single-pacing saved pass[0] passes with frontier ledger" 0 single-frontier-ledger.md single-pass-0.md 'bare=0 status=ok structure=0$' --pacing single --cap 1
runx "single-pacing saved pass[1] (Later: replay controls) passes with frontier ledger" 0 single-frontier-ledger.md single-pass-1.md 'bare=0 status=ok structure=0$' --pacing single --cap 1
runx "single-pacing saved pass[2] round block passes with frontier ledger" 0 single-frontier-ledger.md single-pass-2.md 'bare=0 status=ok structure=0$' --pacing single --cap 1
nox "single-pacing saved pass[2] verbatim emits no preview findings" single-frontier-ledger.md single-pass-2-full.md '^preview=' --pacing single
runx "single-pacing saved fail[0] (two questions) fails" 1 single-frontier-ledger.md single-fail-0.md '^over-cap=2$' --pacing single --cap 1
runx "single-pacing saved fail[1] (previews other decisions) fails with preview overlap" 1 single-frontier-ledger.md single-fail-1.md '^preview=4:overlap:' --pacing single
runx "single-pacing saved fail[2] (Later: previews frontier) fails with Later preview match" 1 single-frontier-ledger.md single-fail-2.md '^preview=4:later:Q6$' --pacing single
runx "single-pacing saved fail[2] catches alert topics on Later: too" 1 single-frontier-ledger.md single-fail-2.md '^preview=4:later:Q[78]$' --pacing single

round single-same-file-later.md \
  'Round 2' \
  'Scope check: 4 questions asked so far' \
  'Later: delay between attempts' \
  '' \
  '❓ Q4 (after the last attempt): **What happens to an event after its last failed attempt?**' \
  'Context:' \
  '- Webhooks are delivered at least once (user, round 1).' \
  '➡️ My recommendation: **Move it to a dead-letter table.** (verified, user, round 1).' \
  '---' \
  '❓ Q6 (retry delay): **What is the delay between attempts?**' \
  'Context:' \
  '- Today the sender makes one POST (user, round 1).' \
  '➡️ My recommendation: **Exponential backoff.** (verified, user, round 1).'
runx "under single pacing a Later: topic matching another question in the same round file fails" 1 empty-ledger.md single-same-file-later.md '^preview=3:later:Q6$' --pacing single
nox "under round pacing the same Later: line prints no preview finding" empty-ledger.md single-same-file-later.md '^preview='

round single-alt-overlap.md \
  'Round 2' \
  'Scope check: 4 questions asked so far' \
  '' \
  '❓ Q4 (after the last attempt): **What happens to an event after its last failed attempt?**' \
  'Context:' \
  '- Webhooks are delivered at least once (user, round 1).' \
  '➡️ My recommendation: **Move it to a dead-letter table.** (verified, user, round 1).' \
  'Alternatives:' \
  '- (a) Drop it and log. Simplest, but breaks at-least-once delivery (user, round 1).' \
  '- (b) Keep retrying forever. Never loses an event, and the attempt-count decision goes away, but a dead receiver grows the queue.' \
  '---' \
  '❓ Q5 (attempt count): **How many delivery attempts does the sender make before giving up?**' \
  'Context:' \
  '- Today the sender makes one POST (user, round 1).' \
  '➡️ My recommendation: **Five attempts.** (verified, user, round 1).'
runx "under single pacing an alternative previewing another question's topic fails" 1 empty-ledger.md single-alt-overlap.md '^preview=10:overlap:Q5$' --pacing single
nox "under round pacing the same alternative prints no preview finding" empty-ledger.md single-alt-overlap.md '^preview='

round single-later-cites-earlier.md \
  'Round 2' \
  'Scope check: 4 questions asked so far' \
  '' \
  '❓ Q4 (after the last attempt): **What happens to an event after its last failed attempt?**' \
  'Context:' \
  '- Webhooks are delivered at least once (user, round 1).' \
  '➡️ My recommendation: **Move it to a dead-letter table.** (verified, user, round 1).' \
  '---' \
  '❓ Q5 (attempt count): **How many delivery attempts does the sender make before giving up?**' \
  'Context:' \
  '- Failed events go to the dead-letter table (your answer to Q4, after the last attempt).' \
  '➡️ My recommendation: **Five attempts.** (verified, your answer to Q4, after the last attempt).'
runx "under single pacing a later question citing an earlier question in its Context passes" 0 empty-ledger.md single-later-cites-earlier.md 'bare=0 status=ok structure=0$' --pacing single

BASIS_SAMPLES="$EVALS_DIR/interview-recommendation-basis-and-flip/samples/checkable-basis-and-flip.json"
for idx in 0 1 2 3 4; do
  {
    printf 'Scope check: 2 questions asked so far\n\n'
    extract_sample "$BASIS_SAMPLES" pass "$idx"
  } >"$TMP/basis-pass-$idx.md"
  runx "basis-and-flip saved pass[$idx] passes" 0 empty-ledger.md "basis-pass-$idx.md" 'bare=0 status=ok structure=0$'
done

for spec in \
  "0:^basis=[0-9]+:uncheckable$" \
  "1:^basis=[0-9]+:missing$" \
  "2:^flips-if=[0-9]+:uncheckable$" \
  "3:^missing=[0-9]+:flips-if$" \
  "4:^basis=[0-9]+:uncheckable$" \
  "5:^basis=[0-9]+:uncheckable$" \
  "6:^basis=[0-9]+:uncheckable$" \
  "7:^basis=[0-9]+:uncheckable$"; do
  idx="${spec%%:*}"
  pat="${spec#*:}"
  {
    printf 'Scope check: 2 questions asked so far\n\n'
    extract_sample "$BASIS_SAMPLES" fail "$idx"
  } >"$TMP/basis-fail-$idx.md"
  runx "basis-and-flip saved fail[$idx] fails ($pat)" 1 empty-ledger.md "basis-fail-$idx.md" "$pat"
done

round basis-ctx-sourced.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Each retry runs in its own worker (src/retry.ts:12)' \
  '2. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **yes, one entry per failed retry**' \
  'Basis: verified, Context 1'
runx "Basis citing a sourced numbered Context line passes" 0 empty-ledger.md basis-ctx-sourced.md 'bare=0 status=ok structure=0$'

round basis-ctx-judgment.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Each retry runs in its own worker (src/retry.ts:12)' \
  '2. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **no, keep logs quiet**' \
  'Basis: verified, Context 2'
runx "Basis citing a (judgment) numbered Context line fails" 1 empty-ledger.md basis-ctx-judgment.md '^basis=7:uncheckable$'

round basis-judgment-only-ctx.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **no, keep logs quiet**'
runx "a recommendation whose Context only has (judgment) lines and no Basis fails" 1 empty-ledger.md basis-judgment-only-ctx.md '^basis=5:missing$'

round basis-ctx-unverified.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (cache): **Where should the counters live?**' \
  'Context:' \
  '1. Redis has enough capacity (unverified).' \
  '➡️ My recommendation: **Redis.**' \
  'Basis: verified, Context 1'
runx "Basis citing an (unverified) numbered Context line fails" 1 empty-ledger.md basis-ctx-unverified.md '^basis=6:uncheckable$'

round basis-ctx-arbitrary-parens.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (cache): **Where should the counters live?**' \
  'Context:' \
  '1. Redis has enough capacity (estimated by team).' \
  '➡️ My recommendation: **Redis.**' \
  'Basis: verified, Context 1'
runx "Basis citing a numbered Context line with arbitrary parenthetical prose fails" 1 empty-ledger.md basis-ctx-arbitrary-parens.md '^basis=6:uncheckable$'

round flips-if-concise.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (cache): **Where should the counters live?**' \
  'Context:' \
  '1. Redis 7 is already deployed for sessions (user, round 1).' \
  '➡️ My recommendation: **the existing Redis 7 instance.**' \
  'Basis: verified, Context 1' \
  'Flips if: writes fail.'
runx "concise confirmable Flips if condition passes" 0 empty-ledger.md flips-if-concise.md 'bare=0 status=ok structure=0$'

round basis-ctx-mixed-order.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Each retry runs in its own worker (src/retry.ts:12)' \
  '2. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **yes, one entry per failed retry**' \
  'Basis: verified, Context 2 and Context 1'
runx "Basis citing judgment Context line before sourced Context line still passes" 0 empty-ledger.md basis-ctx-mixed-order.md 'bare=0 status=ok structure=0$'

round basis-ctx-plural-lines.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Each retry runs in its own worker (src/retry.ts:12)' \
  '2. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **yes, one entry per failed retry**' \
  'Basis: verified, Context lines 2 and 1'
runx "Basis citing plural Context lines passes when any cited line is sourced" 0 empty-ledger.md basis-ctx-plural-lines.md 'bare=0 status=ok structure=0$'

round basis-ctx-plural-items.md \
  'Scope check: 1 questions asked so far' \
  '❓ Q1 (retries): **Should failed retries write to the audit log?**' \
  'Context:' \
  '1. Each retry runs in its own worker (src/retry.ts:12)' \
  '2. Operators may prefer quieter logs (judgment)' \
  '➡️ My recommendation: **yes, one entry per failed retry**' \
  'Basis: verified, Context items 2, 1'
runx "Basis citing plural Context items passes when any cited line is sourced" 0 empty-ledger.md basis-ctx-plural-items.md 'bare=0 status=ok structure=0$'

TERMS_SAMPLES="$EVALS_DIR/interview-context-unfamiliar-term-upstream/samples/answerable-without-follow-up.json"
for kind in pass fail; do
  count="$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]]))' "$TERMS_SAMPLES" "$kind")"
  for ((idx = 0; idx < count; idx++)); do
    {
      printf 'Scope check: 2 questions asked so far\n\n'
      extract_sample "$TERMS_SAMPLES" "$kind" "$idx"
    } >"$TMP/terms-$kind-$idx.md"
  done
done

runx "context-unfamiliar saved pass[0] passes with empty ledger" 0 empty-ledger.md terms-pass-0.md 'bare=0 status=ok structure=0$'
runx "context-unfamiliar saved pass[0] passes with matrix ledger" 0 term-ledger.md terms-pass-0.md 'bare=0 status=ok structure=0$'
nox "context-unfamiliar saved pass[1] has no undefined terms with empty ledger" empty-ledger.md terms-pass-1.md '^undefined='
nox "context-unfamiliar saved pass[1] has no undefined terms with matrix ledger" term-ledger.md terms-pass-1.md '^undefined='
sed 's/^- \*\*\([^*]*\)\*\*/- \1/' "$TMP/terms-pass-1.md" >"$TMP/terms-pass-1-clean.md"
runx "context-unfamiliar saved pass[1] without legacy Context bold passes cleanly" 0 empty-ledger.md terms-pass-1-clean.md 'bare=0 status=ok structure=0$'
runx "context-unfamiliar saved fail[0] fails with undefined terms on matrix ledger" 1 term-ledger.md terms-fail-0.md '^undefined=3:cluster step$'
runx "context-unfamiliar saved fail[0] fails on empty ledger (missing basis)" 1 empty-ledger.md terms-fail-0.md '^basis=4:missing$'
runx "context-unfamiliar saved fail[1] fails with undefined term on matrix ledger" 1 term-ledger.md terms-fail-1.md '^undefined=5:cluster step$'
runx "context-unfamiliar saved fail[2] fails on empty ledger when Q2 uses a term only Q1's Context defines" 1 empty-ledger.md terms-fail-2.md '^undefined=9:cluster step$'

round cross-ctx-means-fail.md \
  'Scope check: 2 questions asked so far' \
  'Q1: **Do receivers need per-endpoint ordering?**' \
  'Context:' \
  '- Per-endpoint ordering means a later event never arrives before an earlier failed one (user, round 1).' \
  'My recommendation: **yes** (verified, user, round 1).' \
  '---' \
  'Q2: **Should replays pause new traffic for per-endpoint ordering?**' \
  'Context:' \
  '- Replays resend failed events from the store (user, round 1).' \
  'My recommendation: **yes** (verified, user, round 1).'
runx "a term defined with 'means' in Q1's Context fails undefined= when Q2 uses it without its own Context mention" 1 empty-ledger.md cross-ctx-means-fail.md '^undefined=7:per-endpoint ordering$'

round cross-ctx-means-pass.md \
  'Scope check: 2 questions asked so far' \
  'Q1: **Do receivers need per-endpoint ordering?**' \
  'Context:' \
  '- Per-endpoint ordering means a later event never arrives before an earlier failed one (user, round 1).' \
  'My recommendation: **yes** (verified, user, round 1).' \
  '---' \
  'Q2: **Should replays pause new traffic for per-endpoint ordering?**' \
  'Context:' \
  '- Per-endpoint ordering means a later event never arrives before an earlier failed one (user, round 1).' \
  'My recommendation: **yes** (verified, user, round 1).'
runx "a term defined with 'means' passes when each question's own Context mentions it" 0 empty-ledger.md cross-ctx-means-pass.md 'bare=0 status=ok structure=0$'

if [[ "$fails" -gt 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
