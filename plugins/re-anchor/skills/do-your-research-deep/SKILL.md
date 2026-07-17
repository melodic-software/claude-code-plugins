---
name: do-your-research-deep
description: "Escalate research discipline to a heavy verification fan-out: enumerate every load-bearing claim made so far and dispatch fresh-context subagents to verify each against a primary source, then report a per-claim ledger. Use when: 'deep research pass', 'verify every claim', 'audit all our claims', 'we've made a lot of load-bearing claims', or when your own judgement is the suspected bias across many claims. For a single inline re-anchor + audit, use the sibling do-your-research."
user-invocable: true
disable-model-invocation: false
---

# Do your research — deep

The verification-fan-out tier of the sibling `/re-anchor:do-your-research`.
Same research discipline; heavier execution. Where the base skill re-anchors
and audits inline in the current context, this one fans fresh-context
subagents out over every load-bearing claim so far — the execution tier the
base skill's context cannot provide from within itself.

The shared method — re-anchor, audit, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
The discipline this re-anchors and its portable baseline live in the sibling
[`do-your-research`](../do-your-research/SKILL.md). Read both; this file adds
only the fan-out delta. There is no separate copy of the discipline here —
update the sibling and this tier follows.

## When this tier, not the inline audit

Reserve the fan-out for when the accumulated claims are load-bearing enough
to justify the subagent cost: a long session with many concrete specifics
the rest of the work now rests on, or where your own judgement is the
suspected source of bias across many claims — a self-check in the context
that produced the claims is weak by construction. For a single unbacked
claim or a short session, the inline audit in the sibling is the right tool;
this tier is overkill.

## The fan-out

Run this in place of the base skill's inline audit and correct-forward steps:

1. **Enumerate.** List every load-bearing claim made so far — concrete
   specifics (paths, defaults, flags, signatures, "standard X"), asserted
   facts, and premises the work now depends on. Do not spot-check one.
2. **Fan out, throttled.** Dispatch fresh-context subagents (blind to the
   reasoning that produced each claim) to verify each against a PRIMARY
   source, not the same recall that produced it. Throttle the dispatch in
   bounded waves rather than launching one agent per claim at once — a
   sustained wide fan-out trips server-side burst overload (529s) and loses
   agents mid-run. Cap concurrency to a modest wave (roughly a dozen or
   fewer at a time); lower-tier worker models are sufficient for per-claim
   verification and dodge burst overload. Process the claims wave by wave.
3. **Retry the failed subset only.** If an agent errors or times out, retry
   that claim once; on a second failure mark it unverifiable. Never
   blind-re-run the whole fan-out to recover a few stragglers — re-dispatch
   only the claims that failed.
4. **Merge and correct.** Fold the returns together, correct every falsified
   or unbacked claim THIS turn, and surface anything that stays
   unverifiable rather than smoothing over it.
5. **Report a per-claim ledger.** One list keyed by claim: verified /
   corrected / unverifiable, each with the source that resolved it.

## What this skill does NOT do

- **Not a lighter inline pass.** For a single re-anchor + audit without the
  subagent cost, use the sibling `/re-anchor:do-your-research`.
- **Does not fabricate a citation or a violation.** An honest per-claim
  "verified" or "stays unverified" is the right output when true; the fan-out
  never manufactures findings to look diligent.

## Gotchas

- **Throttle is not optional at scale.** The failure mode is a claim-heavy
  session firing one agent per claim simultaneously; the wave cap and
  failed-subset retry above are what keep the fan-out reliable, not nice-to-
  haves.
- **Blind subagents, or it is not fresh context.** An agent handed the
  reasoning that produced a claim re-derives the same error. Verify against
  the primary source, not the argument for the claim.
