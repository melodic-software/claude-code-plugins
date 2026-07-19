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

Recommendation-locked this round under the user's standing pre-authorization (same basis as
the WP2/WP3 round): hub doc `reference/guardrails.md` with leaf docs under
`reference/guardrails/` (`isolation-ladder.md`, `work-classes.md`, `security-review.md`,
`admission-policy.md` — the D1 example split, adopted); class tokens `C1`–`C5` and level
tokens `L0`–`L3` carried verbatim from T3/T2; security binding = a contract-owned JSON
document in the settings-as-code home (`schema_version` from `"1.0"`); non-security remaps =
an ADDITIVE `guardrails` section of the WP1 repo-local binding; admission decision table
serialized as JSON inside the security binding.

Prerequisite: the WP4 implementation PR merged (`reference/trigger-dispatch.md` exists — the
admission leaf cites its seam; the interim is safe via WP4's fail-closed absent-binding
clause).

### Phase 1: Guardrail hub + leaf docs [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/guardrails.md` | Create | The hub/spine (D1): the five-class × five-column matrix table imported from T3 unchanged (C1 read-only / C2 mechanical / C3 scoped / C4 structural / C5 untrusted-provenance × min-isolation / verification / merge policy / cost tier / escalation), one-line class and column definitions, and the glance-layer rule — this table alone answers "what governs class X"; every deeper question routes to a named leaf. Permission-posture note per D8 (one line: L1 = attended ergonomics tier; L2+ = the boundary is the control). Escalation event classes per D6 (gate failure, verification divergence, admission rejection, demotion, structural-class plan approval, untrusted-provenance always) with the routing obligation (org-bound routes in the security binding) and payload (work-item ref + trace link); mechanism = the governed queue itself (human-gated item + optional channel notification via the trigger contract's acknowledgment symmetry — no second channel). Boris step-4 sentence cited as the matrix's source framing. Zero vendor/fleet names. |
| `plugins/autonomy/reference/guardrails/isolation-ladder.md` | Create | T2 ladder normative text: L0–L3 level definitions, attendance × input-provenance axes, the falsified trigger-source axis recorded as rejected (with reason), L2 unattended floor, fail-closed rule where L2 unavailable (block + name compliant paths, no silent degrade), permission-posture line per D8. Instances org-supplied; free-path substrate CLASSES named as marked examples only. |
| `plugins/autonomy/reference/guardrails/work-classes.md` | Create | Per-class detail: risk-property bundle per class (blast radius, reversibility, provenance, verifiability) — stating explicitly that C1 "read-only" scopes REPO surfaces and permits governed-queue/tracker writes (work-item filing, no repo mutation; the WP6 stress-test's F8 disambiguation) and that C5's min-isolation cell is the L3 floor WP7's C5-dispatch gate cites, per-cell promotion triggers (D3 shape: evidence predicate over queryable telemetry per the telemetry contract; promotion = human-ratified knob flip recorded as a reviewable change on the governance surface; demotion = automatic fail-closed on contrary evidence, re-earn from there). Suggested default predicates (org-bindable values): C2 auto-merge — ≥ 20 autonomous C2 completions over ≥ 14 days with 100% deterministic-gate pass and 0 human-reverted merges; C3 AI-review advisory→blocking — ≥ 30 advisory reviews with 0 human-confirmed missed-blocking findings. C4/C5 merge never promotes. Demotion evidence set: any post-merge gate failure, any human-reverted merge, any verification divergence — one event suffices. |
| `plugins/autonomy/reference/guardrails/security-review.md` | Create | The #241 security-review policy contract as the verification-column leaf: two layers (deterministic scanners + AI security review), per-layer blocking knob (advisory/blocking per class, bound on the governance surface), free-path scanners default, paid SKUs advisory + explicit opt-in with cost surfaced. |
| `plugins/autonomy/reference/guardrails/admission-policy.md` | Create | The D7 admission-policy content the WP4 seam enforces: decision-table shape (signal-surface class × initiator provenance × work class → disposition `autonomous-eligible` / `human-gated` / `audited-rejection`) + caps (`autonomous_concurrency`, `items_per_run`). Shipped defaults verbatim from D7: C1/C2 autonomous-eligible within caps regardless of provenance; C3 per-item human admission; C4/C5 human-gated; provenance recorded, never trusted as isolation. Default cap values (org-bindable): `autonomous_concurrency: 1`, `items_per_run: 3` — conservative Boris trust-before-scale floor. Serialization: the `admission` object of the security binding (Phase 2 schema). |

**Sanity Check:**

- Hub glance test: `grep -c '| C[1-5] |' plugins/autonomy/reference/guardrails.md` = 5 (matrix rows present) and hub contains zero level-definition prose (`grep -c 'microVM' plugins/autonomy/reference/guardrails.md` = 0 — depth lives in leaves)
- `grep -c 'audited-rejection' plugins/autonomy/reference/guardrails/admission-policy.md` ≥ 1
- `grep -ci 'fail-closed' plugins/autonomy/reference/guardrails/isolation-ladder.md` ≥ 1
- Promotion defaults present: `grep -c '20 autonomous C2 completions' plugins/autonomy/reference/guardrails/work-classes.md` ≥ 1 and `grep -c '14 days' plugins/autonomy/reference/guardrails/work-classes.md` ≥ 1
- Vendor+fleet deny-list sweep exit 0; lychee lane passes

### Phase 2: Binding schema (two governance surfaces) [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` | Create | Contract-owned JSON Schema for the security binding document that lives in the settings-as-code home (outside agent blast radius per D2): `schema_version` (const "1.0"), `executor_class` (`self-operated` \| `vendor-hosted` — the merge-policy gating input, security-surface data per the trigger contract), `dispatch_posture` (`autonomous-enabled` \| `human-gated-only`, default `autonomous-enabled` — an org may intentionally record its security settings while keeping every dispatch human-gated; the PR-review finding that a missing L2 entry must not conflate that deliberate posture with an invalid binding), `isolation_bindings` keyed by EXECUTION SURFACE (org-named surface id — e.g. the CI pool, a self-run host class; the PR-review finding that a flat level→substrate map lets one surface's L2 binding satisfy the check while a different dispatch surface has no boundary at all) → level token → substrate instance id + probe evidence ref + `runtime_markers` (the per-surface TRUSTED identifying markers the trigger contract's dispatch seam matches platform-attested runner context against — a key/value set drawn from metadata the executing workload cannot forge, e.g. attested runner-pool/label identity; serialized HERE, on the agent-unwritable security surface, so surface attestation never falls back to the repo-local recorded id), `merge_policy` (per class, capped per matrix), `verification_blocking` (per layer per class), `promotion_state` (per PROMOTABLE cell only: state + ratifying change ref + evidence window), `escalation_routes` (event class → org route), `admission` (classification rules — the signal→work-class mappings the trigger contract's adapters stamp from, e.g. label→class for tracker-vcs-event — plus decision-table rules with a `"*"` wildcard per axis and most-specific-wins precedence (full triple > two axes > one axis > default), optional per-rule `override_justification`, and caps `autonomous_concurrency` / `items_per_run`). `additionalProperties: false`; fail-closed semantics documented in-schema (absent/invalid security binding blocks autonomous dispatch). |
| `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` | Create | Validates a security-binding document against the schema + semantic rules the schema cannot express: merge-policy caps never exceed the matrix (C4/C5 human always; `executor_class: vendor-hosted` caps every class at human-gated); every surface bound under `dispatch_posture: autonomous-enabled` must declare non-empty `runtime_markers` (else the dispatch seam could never attest the actual surface and every dispatch would fail closed as unattestable), and marker sets must be PAIRWISE UNAMBIGUOUS under joint satisfiability — two conjunctive predicates are compatible (and the binding REJECTED) unless they require CONFLICTING values for at least one shared key, since a runtime context carrying the union of two non-conflicting predicates matches both (subset/identity checks alone miss e.g. `{pool: blue, region: us}` vs `{pool: blue, os: linux}`); the dispatch seam still requires EXACTLY ONE matching surface at runtime, failing closed on zero or multiple matches — the validator-level joint-satisfiability rejection is what keeps that runtime rule from turning validly bound fleets into ambiguity outages; isolation verdicts are PER SURFACE and CLASS-AWARE: each bound surface resolves, per work class, eligible (its bound level meets that class's min-isolation matrix cell — L2 is the floor for any autonomous dispatch, C5 requires L3) or blocked — admission/executor resolution must name the surface a dispatch would run on AND the item's work class, and verifies the surface meets the class's minimum at dispatch time, so an L2-only surface is never selected for a C5 item (even after human admission or a later policy change) and an unbound surface is blocked even when a sibling surface is bound; under `dispatch_posture: autonomous-enabled` it is an ERROR when NO bound surface reaches L2 (fail-closed, compliant paths named) — under `human-gated-only` the binding validates and the verdict reports blocked autonomous dispatch as the declared posture, not a defect; a `promotion_state` entry for a non-promotable cell (C4/C5 merge) is rejected; admission defaults not weaker than shipped defaults without the rule's `override_justification` (declared in the schema, so a justified override validates); every bound isolation level carries probe evidence. Plus an EVALUATION mode: given a binding + an evidence source, resolves the EFFECTIVE promotion state — the bound knob is a ceiling; live contrary evidence (gate failure, reverted merge, verification divergence) lowers it at evaluation time without writing the binding (automatic demotion has no write-back actor by design: the binding is agent-unwritable; the demotion event additionally files an escalation item requesting the human-ratified binding update). This evaluation is a LIVE-PATH OBLIGATION, not a demo artifact: the admission seam and the merge disposition MUST resolve the effective state (querying the promotion-evidence telemetry) before every autonomous dispatch/merge decision — reading the raw `promotion_state` alone is non-conforming, and unavailable evidence telemetry fail-closes to the unpromoted default — the checker's evaluation mode exists to exercise the same resolution mechanically. Exit contract 0/1/2. |
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Document the two-surface split + layered resolution order (org-policy-home defaults → settings-as-code per-repo security binding → repo-local non-security remaps in the WP1 binding's additive `guardrails` section: class→label strings, cost-tier→model names) — INCLUDING the security binding's resolvable locator: the org-policy home carries the repo→security-binding-document registry the dispatch seam resolves the binding through when settings-as-code is a separate repository — and for SECURITY resolution the org-policy-home identity itself must come from an agent-unwritable bootstrap, never the repo-local binding (the binding seam's known limitation that `org_policy_home` may persist repo-locally is tolerable for non-security defaults only; a repo-writable pointer would let an agent redirect the whole chain to a forged policy repository with a forged registry, binding, and matching runtime markers): the seam pins the org-policy-home identity from org-level platform configuration outside repo blast radius (an org-level setting/variable repo agents cannot write) or the executor's trusted deployment config, and any security resolution that would depend on a repo-writable pointer — or an unresolvable locator — fail-closes autonomous dispatch with the compliant path named. Fail-closed on absent/invalid security binding; documented defaults only for non-security axes. |

**Sanity Check:**

- `check-security-binding.mjs` exit 0 on a fixture-valid document, exit 1 on each negative fixture: C4 merge_policy `auto`, `executor_class: vendor-hosted` with any non-human-gated merge row, `promotion_state` entry for a C4 cell, missing probe evidence, missing L2 under `dispatch_posture: autonomous-enabled`, admission weakened without `override_justification`; exit 0 with a blocked-dispatch verdict on the missing-L2 + `human-gated-only` fixture (deliberate posture, not a defect) (fixtures under `evals/fixtures/`)
- Evaluation mode: a promoted-C2 binding + contrary-evidence fixture resolves the EFFECTIVE state demoted (exit output asserts the ceiling was lowered without modifying the binding file)
- Schema declares `executor_class` and `override_justification` (`grep -c 'executor_class' …schema.json` ≥ 1; `grep -c 'override_justification' …schema.json` ≥ 1)
- Schema `additionalProperties: false` present (`grep -c '"additionalProperties": false' …schema.json` ≥ 1)
- `claude plugin validate --strict` exit 0

### Phase 3: Guided-setup guardrail slice [TODO]

Extends the `setup` skill: detect → bind → live-validate → fail-closed (D4), always
detect-diff-reconcile against existing org guardrail surfaces (D5 — sandbox configs, branch
protections, review workflows), never greenfield-assume, never silently overwrite.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Guardrail slice: detect available substrates per level per machine surface; bind level→substrate into the security binding; LIVE-VALIDATE before recording — the empirical probe per substrate class: denied-egress smoke test inside the boundary (a network fetch to a well-known external host MUST fail) + host-credential-path read attempt (MUST be absent/denied); a binding lands only after the probe transcript proves the boundary; probe evidence ref recorded in the binding. Fail-closed verify: no L2 substrate on a surface → autonomous dispatch blocked for that surface, compliant paths named. Security-review slice folded here per D5 (one guardrail slice, no separate near-duplicate capability). Paid scanner SKUs advisory + opt-in with cost surfaced. |
| `plugins/autonomy/skills/setup/templates/isolation-probe.md` | Create | Probe recipe per substrate class (container / OS-sandbox wrap / VM-microVM), parameterized, vendor names as marked examples only: egress-denial probe command shape, credential-absence probe shape, expected-failure assertions, transcript capture shape. |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Add guardrail-slice cases: substrate detection interview, probe-before-bind ordering, fail-closed no-L2 path, detect-diff-reconcile against a pre-existing branch-protection surface, paid-SKU advisory refusal-to-default. |
| `plugins/autonomy/README.md` + `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Capability list + description + minor version bump. |

**Sanity Check:**

- `/skill-quality:check` + `validate-evals` pass
- `grep -c 'probe' plugins/autonomy/skills/setup/templates/isolation-probe.md` ≥ 3
- `grep -ci 'detect-diff-reconcile' plugins/autonomy/skills/setup/SKILL.md` ≥ 1
- Fleet-name sweep exit 0

### Phase 4: Live-validation demonstration + gates [TODO]

Acceptance probe, BOTH paths mandatory: (positive) run the Phase 3 probe recipe against a
REAL, PROVISIONED egress-denied boundary — the CI job on this public repo (free minutes)
launches a nested no-network container via the container runtime present on the hosted
Linux runner image (network mode none / internal-only, no host env or secrets passed in)
and executes the probe INSIDE it; the outer job keeps normal networking, so the probe's
egress-denial assertion is satisfied by a genuine boundary the job itself created — never
by the bare runner (which has outbound access and would fail the assertion) and never by a
hardcoded "denied" — transcript shows denied egress + absent credentials inside the
boundary, proving the probe DETECTS a genuine boundary; (negative) the fail-closed path is demonstrated by
validating an `autonomous-enabled` binding with a MISSING L2 entry and observing the
blocked-dispatch error; the deliberate `human-gated-only` posture validates separately with
its blocked-dispatch verdict reported as declared, not as a defect. A
fixture security binding referencing the positive probe's evidence passes
`check-security-binding.mjs`; the demotion evaluation fixture (Phase 2) runs here as part of
the demo record. Then the full gate roster (WP2 Phase 4): `validate-plugins.sh`,
`run-plugin-tests.sh`, `validate-plugin-contracts.mjs`, markdown/typos/lychee,
`claude plugin validate --strict`, catalog regen. Near-duplicate audit statement: security
review folded into the one guardrail slice (D5); escalation composes the governed queue — no
second channel created.

**Sanity Check:**

- Positive probe transcript (provisioned no-network container on the CI runner: egress denied + credentials absent inside; outer job networked) attached to the PR body
- Negative path: `check-security-binding.mjs` exit 0 on the demo binding, exit 1 on the missing-L2 `autonomous-enabled` fixture, exit 0 + declared blocked-dispatch verdict on the `human-gated-only` fixture
- Demotion evaluation output (effective state lowered, binding file unchanged) in the demo record
- All gate scripts exit 0; catalog in-sync
- Near-duplicate audit statement present in the PR body

## Blast radius

MEDIUM-HIGH — one plugin's files, but this contract governs every autonomous dispatch
decision (admission), every isolation binding, and the promotion path to the closed loop;
security-posture content raises the review bar. Fully git-revertible; the security binding
itself ships as schema + fixtures only (no live org binding lands in this package).

## Stress-test summary

Fresh-context plan review (WP4+WP5 batch): 14 findings, verdict FIX-THEN-SHIP, all folded.
WP5's share — F1b (HIGH, cross-package): the hosted human-merge-gate cap keyed on an
executor class the schema never carried → `executor_class` added to the security schema and
enforced by the check; F9 (MED): `override_justification` was required by the check but
undeclared under `additionalProperties: false` → declared in the admission-rule sub-schema;
F10 (MED): automatic demotion had no write-back actor against an agent-unwritable binding →
eval-time evidence-gating (bound state is a ceiling; live contrary evidence lowers the
effective state; the demotion event files an escalation item requesting the human-ratified
update), with an evaluation-mode fixture in the check and the demo; F11 (MED): the
fail-closed pivot alone never proved the probe detects a real boundary → positive probe
mandatory against a free-tier CI container, negative path demonstrated separately; F12
(LOW): fragile `grep -c '20'` → full-phrase grep; F13 (LOW): 3-D admission table gains a
`"*"` wildcard + most-specific-wins precedence, and promotion entries for non-promotable
cells are rejected; F14 (LOW, symmetry): the D8 backlog seeds are echoed in Open questions.
The classification-rules half of F1a lands here as the `admission.classification` schema
content (the WP4 contract's adapters stamp from it).

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — Phase 2's schema serializes Phase 1's admission leaf;
Phase 3 wires Phase 2's binding; Phase 4 probes Phase 3's recipe. Cross-package: after the
WP4 implementation PR (admission seam exists to cite).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | normative security-policy authoring, tightly coupled T2/T3 imports |
| 2 | main-session | schema + semantic-validator judgment |
| 3 | main-session | setup-skill judgment, probe design |
| 4 | main-session | live probe + gate runs |

## Open questions

- Fleet materializations (live org security binding, workflow gates, scanner wiring) —
  /work-items backlog post-merge (Brief out-of-scope, triggers recorded).
- Interactive escalation UX — WP7 runner design pack (Brief trigger).
- D8 backlog seeds (auto-mode classifier tuning + safe-command allowlist distribution) —
  carried in the Brief with named triggers; filed via the work-items flow.

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Leaf split: 4 leaves under `reference/guardrails/` | Phase 1 file set | Brief D1 names exactly these four as the example split; each maps to one matrix column/axis |
| Hub-subdirectory layout (first `reference/` subdir) | Phase 1 paths | Progressive-disclosure hub needs its leaves grouped; flat names would couple hub prose to 4 sibling filenames |
| Promotion defaults: C2 ≥20 runs/≥14 days/100% gates/0 reverts; C3 ≥30 advisory/0 missed-blocking | work-classes leaf | D3 requires suggested defaults at architect; values conservative per Boris trust-before-scale (org-bindable) |
| Cap defaults `autonomous_concurrency: 1`, `items_per_run: 3` | admission leaf + schema | D7 requires caps; floor values bound total fan-out at the trust-earning stage |
| Security binding as JSON + JSON Schema + semantic validator | Phase 2 deliverables | WP1 binding precedent (schema-versioned JSON, stop-and-report on invalid); schema alone cannot express matrix caps |
| `executor_class` + classification rules live on the security surface; promotion is eval-time evidence-gated (ceiling semantics) | Phase 2 schema + check | Stress-test F1b/F10: gating inputs must sit outside agent blast radius; an agent-unwritable binding cannot receive an automated demotion write |
| Demo pivots to fail-closed path when no container substrate exists | Phase 4 | D4 makes fail-closed the required behavior — the pivot demonstrates the contract, not a skipped demo |

[FALLBACK — confirm or override] `check-security-binding.mjs` as a NEW deliverable (Phase 2)
— invented beyond the Brief on the WP2/WP4 enforcement-surface precedent. Flag if unwanted.

## Handoff to implementation

### User-approval gates

- The binding-check script above is [FALLBACK] — surface before authoring if contested.
- Any change to the shipped admission defaults or matrix cells during implementation → STOP
  (these are T3/D7 user-locked content, not implementation discretion).
- Any scope expansion beyond the four phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same commit
as each phase; live probe per Phase 4 with the documented fail-closed pivot.

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-guardrails`); gates
re-run in full at Phase 4; PR body carries the probe transcript + near-duplicate audit
statement + this PLAN in a `<details>` block at close-out.
