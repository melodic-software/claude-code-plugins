# ai-ladder-wp3-return-accounting

## Brief

### TLDR

Return-accounting convention (T5): a lightweight, tracker-resident record captured at the task
boundary of autonomous-class work, answering Boris's two return questions (counterfactual +
manual-effort band), joined to machine cost telemetry by the WP2 work-item attribute. No new
capability, no new cost; agents prompt and aggregate but never estimate return fields.

### Goal

Any adopting org can capture return data — would-have-done-anyway plus manual-effort band — at
every autonomous-class task boundary, as a tracker-resident record joinable to its cost
telemetry by work-item ID, via guided setup, with zero paid dependencies.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Package scope: WP3 ships (i) the return-accounting convention doc and (ii) the capture slice of the guided-setup capability, both in the capability-distribution home (WP1 D4). "No new capability" (T5) means no standalone estimation/reporting product — not zero setup surface; the convention answers nobody's return questions if no surface ever asks them. Fleet dogfood wiring = work-item backlog, out of package. |
| D2 | Data model imported from T5 unchanged: three layers — (1) machine/deterministic: automation cost from existing session telemetry + lifecycle metadata from tracker timestamps; (2) human-attested: counterfactual yes/no/partial + manual-effort band; (3) agent/LLM: prompts for layer 2 at the task boundary, analyzes/aggregates over 1+2, NEVER estimates return fields (revisit trigger: models proven capable at effort estimation). Capture scope: autonomous-class work only (classes per T3 matrix); interactive exempt; expansion trigger: post-aggregation spend concentrating in interactive work. |
| D3 | Record shape: the contract defines the record SCHEMA — work-item ID (WP2 D3 namespace token), counterfactual enum, effort band, timestamp, attestor role — and the tracker binding seam decides the surface: native tracker fields where the tracker supports them, structured comment as the universal floor (every tracker has comments; custom fields are entitlement/vendor-specific). Exact schema tokens and comment template at architect. |
| D4 | Effort bands: fixed contract-owned ordinal scale, five contiguous bands — `<1h`, `1–4h`, `4h–1d`, `1d–1w`, `>1w`. Deliberate deviation from the T5 draft (`<1h / 1–4h / 1–2d / 1w+`), which left 4h–1d and 2d–1w unmapped. Org-custom bands rejected: breaks cross-org aggregation (same argument that rejected per-adopter reverse-DNS in WP2 D3). |
| D5 | Prompt: Boris's two thread questions near-verbatim as the canonical basis — "would you have spent engineering effort on this anyway?" (yes/no/partial) and "what would it have cost in manual eng-hours?" (band). Two fields only; non-blocking at the task boundary; a skipped prompt is recorded as unattested — missing data stays visible, never imputed or estimated. Exact template wording at architect. |
| D6 | Cost-join mechanics: join-key-only. The return record and the cost telemetry both carry the work-item ID (WP2 D3 attribute); cost values are never duplicated into the tracker record; the join happens sink-side at query time (WP2 D5 query-on-read). Aggregation/reporting transport stays WP2's sink concern. |
| D7 | Guided-setup capture slice is discovery-first per WP1 D7: detect the adopting org's tracker and close-flow; wire the prompt at the task boundary where the surface is machine-editable and reviewable (WP1 D6 — always as reviewable changes); advise with steps + cost surfaced where the surface is GUI-only or entitlement-gated. |

### Constraints

- Any fleet repo name in normative contract text is a defect (WP1 acceptance criterion).
- Zero new cost by default; no paid dependency on any capture path.
- Telemetry is never presented as return — usage measures activity, not return (T5); the
  machine layer informs the cost side of the join only.
- No agent/LLM surface estimates, imputes, or backfills the two human-attested fields.
- Band set and counterfactual enum are contract-stable: changes are reviewed contract
  migrations, never per-org variation.
- Boris-alignment is the standing acceptance criterion: two human fields = his two questions,
  convention-before-capability, no step-skipping, trust before scale.

### Acceptance criteria

- Convention doc names roles and contract vocabulary only; record schema precise enough that
  architect fills mechanics without reopening the contract.
- The record consumes the WP2 D3 work-item attribute as-is — no modification to the WP2
  contract required.
- One conforming path demonstrates: autonomous-class work item closes → tracker-resident
  return record exists → joinable to that item's cost telemetry by work-item ID at the sink.
- Prompt carries exactly two fields, non-blocking; a skip is visible as an unattested record.
- No capability in the package estimates return fields or reimplements a native tracker or
  telemetry surface.
- Guided setup takes an adopter to the capture-enabled state as reviewable changes with zero
  paid dependencies.

### Captured assumptions

- Boris's two return questions come from his X thread (post 3), not the "Step & your role"
  table; verbatim capture is durable in design-threads T5. The table doc (now on disk:
  `docs/topics/ai-adoption-ladder/design/boris-step-and-your-role.txt`, source Google Doc linked from
  wayfind issues #239–#247) carries the related "is this something an engineer would have
  done?" variant — the thread wording is canonical for the prompt.
- The claude.ai artifact endpoint is intermittently erroring; the Google Doc is the reliable
  re-anchor copy.
- The five-band contiguous scale is a deliberate correction of the T5 draft's gaps, locked
  under the round's recommendation pre-authorization.
- Tracker lifecycle metadata (layer 1b) is derivable from tracker exports/timestamps without
  new instrumentation.

### Out-of-scope (deferred with triggers)

- Aggregation/reporting transport — WP2 sink concern; join is query-side.
- Interactive-work capture — trigger: post-aggregation spend concentrates in interactive work.
- Per-class precision graduation (matrix column) — trigger: aggregate proves need.
- Fleet dogfood wiring (close-flow hooks, tracker config) — work-item backlog; trigger: WP3
  build lands.
- Return-field estimation by models — trigger: models proven capable at effort estimation
  (conditional constraint, revisit then).

### Deferred questions

- Exact record schema tokens + structured-comment template — `/architect`.
- Exact prompt template wording (two questions, skip affordance) — `/architect`.
- Tracker binding-shape catalog (native-field vs comment per tracker class) — `/architect`.
- Band label spellings/serialization — `/architect`.

## Plan

(unfilled — /architect)
