---
name: do-your-research
description: "Re-anchor research and no-assumptions discipline mid-session, then self-audit and correct the current work. Use when: 'do your research', 'you're guessing', 'cite that', 'stop assuming', 'evidence, not vibes', 'you skipped verification', 'that's training-data recall', 'research this properly', or at conversation start to set the posture. For a heavy verification fan-out over every load-bearing claim so far, use the sibling do-your-research-deep."
user-invocable: true
disable-model-invocation: false
---

# Do your research

A drift corrector for research discipline. The method — re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this
is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to research discipline.

## The discipline this re-anchors

Research and verification before assertion. Resolve its source of truth
per the method doc's ladder: if the consuming project states a
research/verification discipline in its own `CLAUDE.md` or `.claude/rules/`,
re-anchor THAT. Otherwise re-anchor this portable baseline:

- **Assert nothing you cannot point to a source for.** A claim labelled
  "known", "obvious", or "from memory" is unverified until a fetched
  source or the live environment backs it.
- **Verify every concrete specific.** A path, filename, default, flag,
  signature, or any "standard/conventional X" is a claim — check it
  against an authoritative source or the actual environment before stating
  it as fact, most critically right before the user acts on it.
- **Frame the problem before reaching for a solution.** Name what is
  actually being solved; do not let the first solution shape decide it.
- **Never act on ambiguity.** Surface the unknown and resolve it rather
  than assuming a value.
- **Training-data recall is a starting point, not an answer.** Treat it as
  unverified until confirmed from a current, authoritative source.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a claim asserted without a fetched source, or flagged "known" /
  "obvious" / "from memory";
- a concrete specific stated without live or authoritative verification;
- a solution proposed before the problem was framed;
- verification skipped where the environment could have been checked;
- an answer resting on training data alone.

Correct each forward now: research the unbacked claim, verify the specific
against the live environment or an authoritative source, re-derive a
premature solution from the actual problem, and flag whatever stays
unverifiable rather than smoothing over it. Where your own judgement is
the suspected source of bias, re-derive in a fresh-context subagent.

## Escalating to a verification fan-out

When your own judgement is the suspected source of bias across MANY
load-bearing claims — not just the current one — escalate to the sibling
`/re-anchor:do-your-research-deep`. It fans fresh-context subagents out over
every load-bearing claim so far and reports a per-claim ledger; that fan-out
is a heavier execution tier, so it lives in its own skill rather than as an
argument here.

## What this skill does NOT do

- **Not about code cleanliness.** Clean-implementation and comment
  verbosity are out of scope — a simplification or comment-hygiene tool
  fits those.
- **Does not fabricate a citation or a violation.** An honest "nothing to
  correct" or "this stays unverified" is the right output when true.

## Gotchas

- "Verifying" a claim against the same recall that produced it is not
  verification — the research-specific trap. Reach for a real source or the
  live environment; where your own judgement is the suspect across many
  claims, `/re-anchor:do-your-research-deep` is the fresh-context escalation.
