---
name: do-your-research
description: "Re-anchor research and no-assumptions discipline mid-session, then self-audit and correct the current work. Use when: 'do your research', 'you're guessing', 'cite that', 'stop assuming', 'evidence, not vibes', 'you skipped verification', 'that's training-data recall', 'research this properly', 'fact-check', 'fact check this', 'make sure that's right', or at conversation start to set the posture. For a heavy verification fan-out — a typed full inventory of the session's claims verified at a configurable depth — use the sibling do-your-research-deep."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session makes claims that need backing
  discipline-batch-rank: 20
  workflow-stage: anytime
  summary: Re-anchor research discipline, then audit and correct the current work
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

### "An authoritative source" is a bar with three dimensions

Naming a source is not clearing the bar. A source has a **tier** — tool output
and docs fetched this turn outrank secondary synthesis; ungrounded recall does
not clear the bar at all until it is promoted. A claim needs **independent
corroboration** — citations that trace back to one upstream pool are one source,
not three. And a claim about anything that ships releases needs a **recency**
check against the current upstream, because first-party docs lag their own
releases.

What clears each dimension resolves down the same ladder as the discipline
itself: what the consuming project declares wins; failing that, the contract
`/discovery:research` states as mandatory disciplines, when the `discovery`
plugin is installed; failing both, the floor below. The floor is this skill's
own baseline, not a copy of a heavier tier's numbers — it is deliberately
lighter, because this tier settles one claim mid-conversation rather than
running a research pass:

- **Tier** — at least one source fetched THIS turn: the live environment, tool
  output, or the upstream artifact itself. Recall, and a summary of a source
  read in place of the source, are both below the floor.
- **Corroboration** — before a claim carries a decision, a second source from a
  DIFFERENT upstream pool. One pool restated by three intermediaries is one
  source; where no second pool exists, say that instead of counting the
  restatements.
- **Recency** — for anything that ships releases, a check against the current
  release or changelog, not only the page that named the value.

Whichever rung resolves, hold all three dimensions and cite the rung that
actually applied.

## Two directions — grounding, and checking what was already said

This corrector runs in both directions. They share the discipline and fail
differently, so knowing which one fired tells you what to look for:

- **Preventive** — grounding a claim BEFORE it is asserted. Fires at the moment
  of assertion; skipping it ships a wrong claim.
- **Detective** — checking claims ALREADY asserted, which is what "fact-check
  that" asks for. Fires after the fact; skipping it leaves a wrong claim
  standing while later work builds on it.

Direction is not the skill boundary — DEPTH is. Both directions run here inline
and in the sibling fan-out below; neither skill owns one direction.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a claim asserted without a fetched source, or flagged "known" /
  "obvious" / "from memory";
- a concrete specific stated without live or authoritative verification;
- a claim resting on one source, or on corroborators that all trace to the same
  upstream pool — corroboration count is part of the bar, not a bonus;
- a version, default, flag, or API claim checked against a source that predates
  the current release, with no changelog cross-check;
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
load-bearing claims — not just the current one — or a request to
"fact-check" the whole session wants provable coverage, escalate to the
sibling `/discipline:do-your-research-deep`. It enumerates a typed full
inventory of the session's claims and verifies each — at a configurable
depth — reporting a per-item ledger; that fan-out is a heavier execution
tier, so it lives in its own skill rather than as an argument here.

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
  claims, `/discipline:do-your-research-deep` is the fresh-context escalation.
