---
description: "Re-anchor research discipline; audit and correct the work and pending recommendations, or fan out to verify every session claim. Use when: 'do your research', 'you're guessing', 'cite that', 'stop assuming', 'evidence, not vibes', 'you skipped verification', 'that's training-data recall', 'research this properly', 'fact-check that', 'make sure that's right', 'go research and update your recommendations', 'are these recommendations grounded', 're-check what you recommended', 'fact-check everything', 'verify every claim', 'audit all our claims', 'deep research pass', or at conversation start."
argument-hint: "[tiered|full]"
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session makes claims that need backing
  discipline-batch-rank: 20
  workflow-stage: anytime
  summary: Re-anchor research discipline, then audit and correct the current work
---

# Do your research

A drift corrector for research discipline. The method, re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this
is not an accusation, lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to research discipline.

## The discipline this re-anchors

Research and verification before assertion. Resolve its source of truth
per the method doc's ladder: if the consuming project states a
research/verification discipline in its own `CLAUDE.md` or `.claude/rules/`,
re-anchor THAT. Otherwise re-anchor this portable baseline:

- **Assert nothing you cannot point to a source for.** A claim labeled
  "known", "obvious", or "from memory" is unverified until a fetched
  source or the live environment backs it.
- **Verify every concrete specific.** A path, filename, default, flag,
  signature, or any "standard/conventional X" is a claim. Check it
  against an authoritative source or the actual environment before stating
  it as fact, most critically right before the user acts on it.
- **Frame the problem before reaching for a solution.** Name what is
  actually being solved; do not let the first solution shape decide it.
- **Never act on ambiguity.** Surface the unknown and resolve it rather
  than assuming a value.
- **Training-data recall is a starting point, not an answer.** Treat it as
  unverified until confirmed from a current, authoritative source.

### "An authoritative source" is a bar with three dimensions

Naming a source is not clearing the bar. A source has a **tier**. Tool output
and docs fetched this turn outrank secondary synthesis; ungrounded recall does
not clear the bar at all until it is promoted. A claim needs **independent
corroboration**. Citations that trace back to one upstream pool are one source,
not three. And a claim about anything that ships releases needs a **recency**
check against the current upstream, because first-party docs lag their own
releases.

What clears each dimension resolves down the same ladder as the discipline
itself: what the consuming project declares wins; failing that, the contract
`/discovery:research` states as mandatory disciplines, when the `discovery`
plugin is installed; failing both, the floor below. The floor is this skill's
own baseline, not a copy of a heavier tier's numbers. It is deliberately
lighter, because this tier settles one claim mid-conversation rather than
running a research pass:

- **Tier**. At least one source fetched THIS turn: the live environment, tool
  output, or the upstream artifact itself. Recall, and a summary of a source
  read in place of the source, are both below the floor. An upstream docs
  page is read through the shared docs lookup
  (`${CLAUDE_PLUGIN_ROOT}/scripts/fetch-docs.sh --cache`, following
  `${CLAUDE_PLUGIN_ROOT}/reference/docs-lookup-procedure.md` with
  `<scripts>` = `${CLAUDE_PLUGIN_ROOT}/scripts` and `<session>` =
  `${CLAUDE_SESSION_ID}`), not a WebFetch summary of it.
- **Corroboration**, before a claim carries a decision, a second source from a
  DIFFERENT upstream pool. One pool restated by three intermediaries is one
  source; where no second pool exists, say that instead of counting the
  restatements.
- **Recency**. For anything that ships releases, a check against the current
  release or changelog, not only the page that named the value.

Whichever rung resolves, hold all three dimensions and cite the rung that
actually applied.

## Two directions. Grounding, and checking what was already said

This corrector runs in both directions. They share the discipline and fail
differently, so knowing which one fired tells you what to look for:

- **Preventive**. Grounding a claim BEFORE it is asserted. Fires at the moment
  of assertion; skipping it ships a wrong claim.
- **Detective**. Checking claims ALREADY asserted, which is what "fact-check
  that" asks for. Fires after the fact; skipping it leaves a wrong claim
  standing while later work builds on it.

Direction is not the tier boundary. DEPTH is. Both directions run in the
inline audit and in the fan-out tier below; neither tier owns one direction.

## Audit. What to look for

Name concrete, located findings (per the method doc's step 2, self-audit):

- a claim asserted without a fetched source, or flagged "known" /
  "obvious" / "from memory";
- a concrete specific stated without live or authoritative verification;
- a claim resting on one source, or on corroborators that all trace to the same
  upstream pool. Corroboration count is part of the bar, not a bonus;
- a version, default, flag, or API claim checked against a source that predates
  the current release, with no changelog cross-check;
- a solution proposed before the problem was framed;
- verification skipped where the environment could have been checked;
- an answer resting on training data alone.

Correct each forward now: research the unbacked claim, verify the specific
against the live environment or an authoritative source, re-derive a
premature solution from the actual problem, and flag whatever stays
unverifiable, naming where you looked, rather than smoothing over it. Where your own judgment is
the suspected source of bias, re-derive in a fresh-context subagent.

## Pending recommendations are an audit unit

Every recommendation the session has put to the user and the user has not
yet settled is audited too, whether it is an option, verdict, default, or
next step. Apply the contract in
[`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md):
ground the affected code and its consumers or blast radius through
`/discovery:explore`, and the authoritative sources the contract names
through `/discovery:research`,
when the `discovery` plugin is installed; without it, do the same reads and
fetches inline. Report each as old → new → why when the evidence moved it,
or unchanged with why, in one of the contract's three outcomes:
`Basis: verified`, `Basis: judgment` (never on a consequential one), or
withheld as an open question naming the evidence that would settle it.
This runs inside the
loop's audit and correct-forward steps, so it is not a step delta.

## The fan-out tier

The inline audit above is the default. Take the fan-out tier instead when the
invocation argument is `tiered` or `full`, or when your own judgment is the
suspected source of bias across MANY load-bearing claims, or a request to
"fact-check everything" / "verify every claim" wants provable coverage of the
whole session. A single fact-check or a short session stays inline: there the
fan-out's subagent cost buys nothing.

**Never inside a batch or a fork.** When this skill runs as a member of a
`/discipline:sweep-all` audit fork, or in any fork, run the inline audit only,
whatever the argument or trigger. Where the fan-out would fit, add a ledger
entry recommending a direct `/discipline:do-your-research tiered` run instead.
The batch is audit-only and keeps its cost bounded by leaving fan-out tiers
out, and a fork cannot spawn the forks a fan-out might reach for.

- **Pointer**: what a fork may spawn,
  [How forks differ from other subagents](https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents).
- **As of**: 2026-10-10.
- **Recheck trigger**: that section changes what a fork may spawn.

**Depth**, resolved once before enumerating: the invocation argument (`tiered`
or `full`) wins; otherwise the configured default,
`${user_config.research_deep_verification}`; otherwise `tiered`. An empty
value, a surviving literal `${user_config.…}` token, and any unrecognized
string all mean `tiered`; never error on a bad value.

Then read [reference/fan-out-tier.md](reference/fan-out-tier.md) before
enumerating: it owns the typed inventory, the throttled dispatch, and the
per-item ledger, and replaces the inline audit and correct-forward steps.

## What this skill does NOT do

- **Not about code cleanliness.** Clean-implementation and comment
  verbosity are out of scope, a simplification or comment-hygiene tool
  fits those.
- **Does not fabricate a citation or a violation.** An honest "nothing to
  correct" or "this stays unverified" is the right output when true.

## Next

/discovery:research <question>

When a claim needs a new multi-source research pass rather than a check of
what the session already said.

## Gotchas

- "Verifying" a claim against the same recall that produced it is not
  verification, the research-specific trap. Reach for a real source or the
  live environment; where your own judgment is the suspect across many
  claims, the fan-out tier is the fresh-context escalation.
