---
name: recheck-against-upstream-deep
description: "Escalate upstream-conformance discipline to a heavy fan-out: dispatch fresh-context subagents doc-by-doc over a whole subsystem, framework, or repo, comparing each surface against its CURRENT official upstream docs, then report an inline divergence ledger. Use when: 'recheck the whole subsystem against upstream', 'audit every surface against the docs', 'deep upstream conformance pass', 'check the entire framework config against upstream', 'we depend on a lot of upstream surfaces and they may have drifted'. For a single inline recheck of the surface in play, use the sibling recheck-against-upstream."
user-invocable: true
disable-model-invocation: false
---

# Recheck against upstream — deep

The fan-out tier of the sibling `/re-anchor:recheck-against-upstream`. Same
upstream-conformance discipline; heavier execution. Where the base skill
rechecks the one surface in play inline, this one fans fresh-context
subagents out over a whole subsystem, framework, or repo — doc-by-doc — the
execution tier the base skill's context cannot cover from within itself.

The shared method — re-anchor, audit, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
The discipline this re-anchors, its portable baseline, and the three
divergence categories (gap / deliberate / undocumented) live in the sibling
[`recheck-against-upstream`](../recheck-against-upstream/SKILL.md). Read
both; this file adds only the fan-out delta. There is no separate copy of
the discipline or the taxonomy here — update the sibling and this tier
follows.

## When this tier, not the inline recheck

Reserve the fan-out for when the upstream surface area is broad enough to
justify the subagent cost: a whole framework's configuration, an entire
integration's API usage, a subsystem that leans on many upstream contracts
at once. For a single surface or a short session, the inline recheck in the
sibling is the right tool; this tier is overkill.

## The fan-out

Run this in place of the sibling's inline audit and correct-forward steps:

1. **Enumerate the surfaces.** List every upstream-dependent surface in the
   subsystem/repo under review — each config block, API call site, infra
   definition, and documented contract the work rests on. Do not spot-check
   one.
2. **Fan out, throttled, doc-by-doc.** Dispatch fresh-context subagents
   (blind to the assumptions that produced each surface) to fetch the
   CURRENT official upstream docs for that surface and classify its
   divergence per the sibling's three categories. Throttle the dispatch in
   bounded waves rather than launching one agent per surface at once — a
   sustained wide fan-out trips server-side burst overload (529s) and loses
   agents mid-run. Cap concurrency to a modest wave (roughly a dozen or
   fewer); process the surfaces wave by wave.
3. **Retry the failed subset only.** If an agent errors or times out, retry
   that surface once; on a second failure mark it unverifiable — an honest
   skip, never a false pass. Never blind-re-run the whole fan-out to recover
   a few stragglers.
4. **Checkpoint the partial ledger mid-run, if a durable slice exists.** So
   a crash mid-fan-out does not lose completed waves, checkpoint the partial
   ledger to the session's durable topic-memory slice when one is available;
   where the session has no such durable store, proceed without it rather
   than asserting a persistence surface. This is the only persistence this
   tier performs — nothing is mandatory beyond it.
5. **Merge and report an inline divergence ledger.** One list keyed by
   surface: its category (gap / deliberate / undocumented) and the current
   upstream source that resolved it. Correct gaps toward upstream this turn;
   re-check that deliberate divergences still hold and flag any the docs have
   overtaken; surface undocumented ones for the human with both options.

## Routing findings onward

- **Category 1 (gap) and category 3 (undocumented) → OFFER work-items
  routing.** When a work-item / issue-tracker capability is installed, offer
  to route the actionable gaps and the undocumented divergences awaiting a
  human decision into tracked work items. Degrade to a prose offer (a listed
  set of would-be items) when no such capability is present — never assume a
  tracker.
- **Category 2 (deliberate) is report-only.** A recorded rationale that
  still holds is not an action item; raise it only when the current docs have
  obsoleted it, at which point it becomes a gap and routes with the others.

## What this skill does NOT do

- **Not a lighter inline pass.** For a single-surface recheck without the
  subagent cost, use the sibling `/re-anchor:recheck-against-upstream`.
- **Does not force persistence.** The mid-run checkpoint is best-effort crash
  safety on a durable slice when one exists; it never mandates a store or
  invents one.
- **Does not fabricate conformance or a finding.** An honest per-surface
  "matches current docs" or "unverifiable" is the right output when true.

## Gotchas

- **Throttle is not optional at scale.** The failure mode is a
  surface-heavy subsystem firing one agent per surface simultaneously; the
  wave cap and failed-subset retry are what keep the fan-out reliable.
- **Blind subagents, or it is not fresh context.** An agent handed the
  assumption that produced a surface re-confirms the same drift. Verify
  against the current upstream doc, not the reasoning for the state.
