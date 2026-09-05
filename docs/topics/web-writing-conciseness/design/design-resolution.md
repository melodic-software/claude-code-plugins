# Design resolution: web-writing-conciseness

outcome: early-exit (light design)
resolved: 2026-09-05
tier: B, with two Tier-A signals noted below

## Why early exit

`/planning:plan`'s Tier-A signals that do apply: this adds a new module (a plugin) and it changes
cross-module integration (four plugins narrow a Boundary to route at the new skill, and four more
gain pointers). The signals that do not apply are the ones the design stage exists to resolve:
there are no types, no data model, no package topology, and no runtime contract. Every artifact in
this change is markdown read by a model.

The surface a design pass would have settled was settled instead by `/planning:interview`, across
18 questions in three rounds, all recorded in `.work/web-writing-conciseness/interview-checklist.md`
with their rejected alternatives. Re-deriving it would be ceremony over a locked contract.

Two threads the interview left open are resolved below rather than deferred into the plan body.

## Component surface sketch

```text
plugins/writing/
  .claude-plugin/plugin.json     name: writing, version 0.1.0, category presentation
  README.md                       what it is, the four properties, the NN/g attribution note
  CHANGELOG.md                    0.1.0 initial
  skills/concise/
    SKILL.md                      the dual-mode skill
    reference/doctrine.md         the four properties, rules, thresholds
    reference/sources.md          per-source drift stamps, no vendored text
    evals/evals.json              six cases
    evals/fixtures/               six fixture inputs
```

## Thread 1 (resolved): doctrine file structure

One file, `reference/doctrine.md`, sectioned by the four properties, not by source. Each rule
carries its source inline. A source-ordered file would make a reader assemble the rule set from
five guides; a property-ordered file gives the model one place per decision.

Universal rules (they govern any prose, agent-facing included) are marked as such and are the ones
`docs-hygiene:write-for-agents` points at. Human-only scannability rules sit in their own section
so that pointer cannot drag bullets and headings into agent-facing text.

`reference/sources.md` carries one entry per upstream source with the four-part drift stamp from
`docs/conventions/upstream-drift/README.md`. No NN/g article text is copied beyond short quotes
with credit.

## Thread 2 (resolved): plugin file topology

`reference/` rather than `context/`, following the marketplace's own split: `context/` holds
procedure a skill loads mid-run, `reference/` holds material a skill cites. The doctrine is cited.

Both files live under `skills/concise/`, not at the plugin root, because a single-skill plugin has
no second consumer and the encapsulation rule lets an intra-plugin path cite work.

## Design defaults audited

| Thread | Resolution | Where settled |
|---|---|---|
| Configurability | No config file in V1; thresholds are a labelled fallback overridable by consuming-repo prose | Interview Q5 |
| Extension points | None; a detector and Vale rules are recorded post-V1 items with promotion paths | Interview Q6 |
| Observability | Not applicable; no hook, no script, no runtime | Interview Q4 |
| Testability | Six fixture-backed eval cases | Interview Q15 |
| Type collaboration | Not applicable; no types | This document |
