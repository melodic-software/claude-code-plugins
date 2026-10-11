# The fan-out tier

Read this once [`../SKILL.md`](../SKILL.md) has chosen the fan-out tier. It runs in place of the
inline audit and correct-forward steps: same upstream-conformance discipline and the same three
divergence categories (gap / deliberate / undocumented), but fresh-context subagents cover a whole
subsystem, framework, or repo doc-by-doc, which one context cannot cover from within itself.

## The fan-out

1. **Enumerate the surfaces.** List every upstream-dependent surface in the subsystem or repo
   under review: each config block, API call site, infra definition, and documented contract the
   work rests on. Do not spot-check one.
2. **Fan out, throttled, doc-by-doc.** Dispatch per [`fan-out.md`](../../../context/fan-out.md):
   blind fresh-context subagents, bounded waves, failed-subset retry. Each subagent fetches the
   CURRENT official upstream docs for its surface and classifies the divergence per SKILL.md's
   three categories. Each reads every docs page through the shared docs lookup, following the
   docs-lookup procedure with the `<scripts>` directory SKILL.md resolved; put both as absolute
   paths in the brief, since a subagent's shell does not expand the plugin variable. The subagent
   runs `bash "<scripts>/fetch-docs.sh" --cache --profile <profile> --out "$out" <slug-or-url>` as
   the procedure's step 1 gives it. The read that settles a verdict follows the procedure's step 6:
   re-fetch with `--max-age 0`, so a cached copy never stands in for the current docs, and read
   raw bytes. A source that is not a docs page keeps its existing route.
3. **Checkpoint the partial ledger mid-run, if a durable slice exists.** So a crash mid-fan-out
   does not lose completed waves, checkpoint the partial ledger to the session's durable
   topic-memory slice when one is available; where the session has no such durable store, proceed
   without it rather than asserting a persistence surface. This is the only persistence this tier
   performs.
4. **Merge and report an inline divergence ledger.** One list keyed by surface: its category
   (gap / deliberate / undocumented) and the current upstream source that resolved it. Correct
   gaps toward upstream this turn; re-check that deliberate divergences still hold and flag any
   the docs have overtaken; surface undocumented ones for the human with both options.

## Routing findings onward

- **Category 1 (gap) and category 3 (undocumented): OFFER work-items routing.** When a work-item
  or issue-tracker capability is installed, offer to route the actionable gaps and the
  undocumented divergences awaiting a human decision into tracked work items. Degrade to a prose
  offer (a listed set of would-be items) when no such capability is present; never assume a
  tracker.
- **Category 2 (deliberate) is report-only.** A recorded rationale that still holds is not an
  action item; raise it only when the current docs have obsoleted it, at which point it becomes a
  gap and routes with the others.

## Gotchas

- **The checkpoint is best-effort crash safety, not a mandated store.** It never invents a
  persistence surface.
- **Never fabricate conformance or a finding.** An honest per-surface "matches current docs" or
  "unverifiable" is the right output when true.
