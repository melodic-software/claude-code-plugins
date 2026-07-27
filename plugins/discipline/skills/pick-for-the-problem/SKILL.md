---
name: pick-for-the-problem
description: "Re-anchor the discipline that a tool, library, framework, language, or approach is chosen to fit the actual problem — not reached for out of habit, availability, incumbency, or preconception — then audit the selection in flight and re-derive it from the problem. Use when: 'pick for the problem', 'right tool for the job', 'which library should we use', 'what framework', 'should we build this or use X', 'is this the right approach', 'you defaulted to X', 'we always reach for X', 'evaluate the options', 'choose a dependency', or at conversation start on a build-vs-buy or technology-selection decision."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: situational  # only at a tool/library/approach selection point
  discipline-batch-rank: 80
  cheatsheet-stage: anytime
  cheatsheet-summary: Re-derive a tool or approach choice from the problem, not habit
---

# Pick for the problem

A drift corrector for selection discipline: the tool must fit the problem,
not the reflex. The method — re-anchor, audit the work in flight, correct
forward, report, and the tone that firing this is not an accusation — lives
in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to selecting a tool, library,
framework, language, or approach.

## The discipline this re-anchors

A selection is a design decision, not a reflex. Resolve the source of truth
per the method doc's ladder: if the consuming project states a
technology-selection or dependency-adoption rule in its own `CLAUDE.md` /
`.claude/rules/`, re-anchor THAT. Otherwise re-anchor this portable
baseline.

**The four selection sins** — an unexamined choice usually traces to one:

- **Habit** — "I always use X." The reach is muscle memory, not analysis.
- **Availability** — "X is already at hand." Convenience picked it, not fit.
- **Incumbency** — "the repo already uses X, so new work assumes X." Current
  state is treated as the requirement.
- **Preconception** — "I came in believing X is the answer." The verdict
  preceded the problem.

**The discipline that replaces them:**

- **Define the actual problem first.** Name what is being solved — the real
  requirements — before any candidate is on the table. Do not let the first
  solution shape decide the problem.
- **Survey the field.** More than one candidate, judged against the stated
  requirements and the plausible future ones (variables that could shift and
  turn a choice into future pain).
- **Walk the preference ladder** — an earlier rung wins when it covers the
  requirements and the plausible future requirements:
  1. **Native** — what the platform, language, or framework already
     provides: no new dependency, no new coupling.
  2. **Official / authoritative** — the first-party or canonical option when
     native falls short.
  3. **Vetted third-party** — only when the rungs above genuinely miss, and
     only if it is well-maintained, well-known, safe, and secure.
- **Every dependency is a coupling point.** Weigh, at adoption time, the
  cost this coupling can impose later: abandonment, a pricing pivot, a
  license change, security posture, and exit cost. A dependency adopted
  without that weighing is an unpriced liability.
- **Building what already exists is a finding.** Re-implementing a solved,
  well-served problem (native or vetted) is a selection error in the other
  direction — name it.

## Mandatory routing — no verdict from memory

When the selection is load-bearing, the field survey and the maintenance /
security / license / adoption judgement must come from CURRENT research, not
training-data recall — a tool's maintenance status, licensing, and security
posture drift constantly. Route to a research capability rather than judging
from memory: `/discovery:research`, or `/discovery:research-deep` for a large
surface. Degrade to an explicit in-thread research pass (fetch the primary
sources yourself and cite them) when that capability is not installed —
never a bare recalled verdict.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2). This fires
both at an explicit choice-time AND over choices already embedded in the
work in flight:

- a tool named before the problem it solves was stated;
- a single candidate with no field surveyed;
- a choice tracing to habit, availability, incumbency, or preconception
  rather than fit;
- a third-party dependency adopted with no maintenance / security / license /
  exit-cost weighing;
- a native or authoritative option skipped straight to third-party;
- a hand-built solution to an already-solved, well-served problem.

Correct each forward now: re-derive the choice from the stated problem, run
(or route) the survey, walk the ladder, and price the coupling. Where the
evaluation is load-bearing, route it to research rather than self-checking
from the same recall that produced the reflex.

## Distinct axis — the incumbency overlap

The incumbency sin here is selection-specific — "the repo uses X, so this
new work uses X". The general interrogation of inherited precedent is
`/discipline:reason-dont-recite`; this skill applies that lens narrowly to a
technology choice and adds the field survey, the ladder, and the coupling
price. Route a broader inherited-design challenge there.

## What this skill does NOT do

- **Does not churn a well-fitted choice.** A tool re-derived from the problem
  and found to fit audits clean — including an incumbent one; the duty is to
  re-derive, not to switch for its own sake.
- **Does not issue a verdict from recall.** A load-bearing evaluation routes
  to research; the skill does not pronounce a maintenance or security verdict
  from memory.
- **Does not fabricate a finding.** A choice already problem-derived and
  field-surveyed audits clean; say so.

## Gotchas

- **The reflex hides as a reason.** "We use X here" and "X is what I know"
  are the incumbency and habit sins wearing the costume of a rationale; a
  real rationale names the requirement X satisfies, not its familiarity.
- **A deep dependency-inventory variant is deliberately deferred.** Auditing
  an entire repo's dependency graph for coupling risk is out of scope here;
  that sibling lands on the first real dependency-inventory audit request,
  not before — not shipped speculatively.
