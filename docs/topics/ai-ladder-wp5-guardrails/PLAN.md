# ai-ladder-wp5-guardrails

## Brief

### TLDR

Guardrail-enforcement package (T2 + T3 + #241 instance): one guardrail contract shaped as a
progressive-disclosure hub (matrix doc as index/spine) with on-demand leaf docs, an org-binding
seam split by governance sensitivity, evidence-gated promotion with automatic demotion, and the
guardrail slice of guided-setup (detect → bind → live-validate → fail-closed).

### Goal

Any adopting org can bind the five-class guardrail matrix to its own instances and get
per-work-class enforcement — isolation floor, verification layers, merge policy, cost tier,
escalation — with the security-sensitive bindings outside agent blast radius, promotion earned
on queryable evidence, and no silent degrade anywhere.

### Locked decisions

| # | Decision |
|---|---|
| D1 | ONE guardrail contract, hub-and-leaves progressive disclosure: matrix doc = index/spine (table + one-line class/column definitions, glance layer resolves the common question); leaf docs load on demand — e.g. isolation-ladder levels, per-class detail + promotion triggers, security-review policy, admission policy (examples, not a fixed list; split at architect). Plus the guardrail slice of guided-setup. Both in the capability-distribution home. Fleet materializations = /work-items backlog. |
| D2 | Org-binding seam: contract-owned schema, one logical binding, two governance surfaces split by sensitivity. Security-sensitive axes (isolation substrates per level, merge policy, per-layer blocking knobs, promotion-trigger state, escalation routes, admission policy) bind in the settings-as-code home — outside the blast radius of agents working in the consuming repo (agent-writable guardrail binding = bypass channel). Non-security mappings (class→label strings, cost-tier→model names) may bind repo-locally per the work-item-tracker binding pattern. Layered resolution: org-policy-home defaults → settings-as-code per-repo binding → repo-local non-security remaps; contract defines resolution order, materialization at architect. Fail-closed on absent/invalid security-sensitive binding; documented defaults only for non-security axes. |
| D3 | Promotion/demotion discipline: contract defines the trigger SHAPE — an evidence predicate over queryable telemetry (verification outcomes per the telemetry contract are the evidence base). Promotion = human-ratified knob flip, recorded as a reviewable change on the governance surface — never automatic. Demotion = automatic fail-closed on contrary evidence (gate failure, human-reverted merge), re-earn from there. Org binds threshold values; suggested defaults at architect. Near-term promotable cells: C2 auto-merge, C3 AI-review advisory→blocking (#241); C4/C5 merge never promotes. |
| D4 | Sandbox-ladder setup slice: detect available substrates per level per machine surface → bind level→substrate in the security binding → live-validate BEFORE recording (empirical probe, e.g. denied-egress smoke test inside the boundary; a binding lands only after the sandbox provably blocks) → fail-closed verify (no L2 substrate → autonomous dispatch blocked for that surface, compliant paths named — no silent degrade). |
| D5 | #241 three-part resolution folds into the matrix structure, nothing ships separate: security-review policy contract (two layers, per-layer blocking knob) = verification-column leaf; security-review setup = part of the one guardrail slice of guided-setup (near-duplicate capability ban); the adjustment/audit layer generalizes matrix-wide — guided-setup always detect-diff-reconcile against existing org guardrail surfaces (sandbox configs, branch protections, review workflows), never greenfield-assume, never silently overwrite. |
| D6 | Escalation column sharpened from DIRECTIONAL: contract defines escalation event classes (gate failure, verification divergence, admission rejection, demotion event, structural-class plan approval, untrusted-provenance always), routing obligation (org-bound routes in the security binding), and payload (work-item ref + trace link, one causal tree). Mechanism reuses the governed queue: escalation lands as a human-gated work item + optional channel notification via the trigger-contract acknowledgment symmetry — no second channel. Only interactive escalation UX stays deferred; trigger: WP7 runner design pack. |
| D7 | Admission-policy content (the trigger contract's admission seam enforces it; this package owns it): decision-table shape — signal-surface class × initiator provenance × work class → disposition (autonomous-eligible / human-gated / audited rejection) — plus caps (autonomous concurrency, per-run items). Shipped defaults: C1/C2 autonomous-eligible within caps regardless of provenance (blocking agent provenance would sever the agent-kicks-off-agent loop), C3 per-item human admission, C4/C5 human-gated. Provenance is recorded input to gating, never trusted as isolation; caps bound total autonomous fan-out. |
| D8 | Permission posture: attended ergonomics (auto-mode classifier tuning, safe-command allowlist distribution) is NOT a matrix column — unattended runs replace per-action prompts with the whole-process boundary; the ladder leaf carries a one-line permission-posture note (L1 = attended ergonomics tier, L2+ = the boundary is the control). Classifier tuning + allowlist distribution = backlog seeds with trigger, not silent drops. |

### Constraints

- Any fleet repo or vendor name in normative contract text is a defect; vendor names appear only
  as marked examples and in binding docs.
- Security-sensitive bindings never live where the agents they govern can edit them.
- Fail-closed everywhere: unavailable substrate, absent/invalid security binding, contrary
  promotion evidence — block and name the compliant path, never degrade silently.
- No new cost by default: free-path scanners and substrates default; entitlement-gated tools
  (e.g. paid code-scanning SKUs) are advisory + explicit opt-in with cost surfaced.
- One queue, one escalation channel (the queue itself); no second claim, dispatch, or
  escalation mechanism.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before scale).

### Acceptance criteria

- Matrix doc's glance layer alone answers "what governs class X" — leaf docs only for depth
  (progressive-disclosure convention conformance).
- Binding schema names the two governance surfaces + layered resolution order; security axes
  fail closed when unbound.
- Promotion is human-ratified + evidence-gated; demotion is automatic; both leave a reviewable
  audit trail on the governance surface.
- Guided-setup slice detect-diff-reconciles existing guardrail surfaces, live-validates
  isolation before binding, and has zero paid dependencies on its default path.
- Admission decision-table defaults match the matrix class defaults verbatim; agent provenance
  is not blocked by default; caps are org-bindable.
- Boris check: step-3 guardrails cell covered (agent sandboxing = ladder; automatic code +
  security review = verification layers; token/model management = cost tiers); step-4 sentence
  ("enforcing the right guardrails for each type of work") instantiated as the matrix; step-3
  trap honored (human-ratified promotion, automatic demotion); step-1 guardrail untouched.
- Auto-mode classifier tuning + allowlist distribution explicitly out-of-scope with named
  triggers, not dropped.

### Captured assumptions

- Verification-outcome telemetry (WP2 contract) is queryable at promotion-evaluation time; until
  wired, promotion evaluation is manual over the same evidence definition.
- Free-path deterministic scanners remain available on the default path; paid code-scanning
  SKUs stay entitlement-gated (re-verified: private-repo CodeQL requires a paid license).
- The work-item-tracker binding precedent (contract-owned schema, org-supplied values,
  stop-and-report on invalid binding) remains the fleet's binding idiom.

### Out-of-scope (deferred with triggers)

- Interactive escalation UX — trigger: WP7 runner design pack.
- Auto-mode classifier tuning + safe-command allowlist distribution — trigger: 1→2 residue
  sweep / standards allowlist-distribution work (backlog seeds).
- Cost ENFORCEMENT (hard spend caps) — trigger: 3→4 transition work; cost tiers here are
  policy vocabulary only.
- Fleet materializations (binding instances, workflow gates, scanner wiring) — /work-items
  backlog post-graduation.

### Deferred questions

- Exact class/level/column/attribute tokens + binding schema fields — `/architect` (with the
  plugin naming pass).
- Leaf-doc file split + glance-layer wording — `/architect`.
- Promotion-trigger default values (run counts, windows) + demotion evidence set — `/architect`.
- Setup-slice probe mechanics per substrate class — `/architect`.
- Admission decision-table serialization format — `/architect`.

## Plan

(unfilled — /architect)
