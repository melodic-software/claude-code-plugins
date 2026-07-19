# ai-ladder-wp7-runner

## Brief

### TLDR

Runner design pack (T4 charter graduation): architect-ready design contract for the
autonomous-drain runner — spine shape + 8 seam specs, lifecycle state model, two-family
stop-criteria taxonomy with terminal-handoff escalation, matrix-derived backend set, and the
topology seam map. Design only: build stays gated on the T4 triggers; the runner-execution
home stays unborn.

### Goal

When the T4 build trigger fires, `/architect` and the build start from a complete,
Boris-aligned design contract instead of a cold charter: every design decision T4 graduated
(composition spine, isolation backends, lifecycle depth, escalation UX, topology) is resolved
in contract vocabulary, every inherited constraint is imported unchanged, and nothing in the
package commits, implies, or starts a build before the trigger earns it.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Scope: architect-ready design contract docs ONLY — charter import (T4 scope boundary, build triggers, substrate stance, inherited constraints, anti-goals) + the five design decisions T4 graduated (composition spine, multi-backend isolation, lifecycle depth, escalation UX, topology) resolved + seam specifications. Capability-distribution home. No code, no skeleton repo, no capability templates; runner-execution home stays unborn until the T4 build trigger fires (WP1 D1); empirical spine validation waits for the trigger. |
| D2 | Composition spine, two-layer: normative contract fixes the spine SHAPE in seam vocabulary — minimal composable orchestration, pluggable sandbox-provider seam × pluggable agent-adapter seam, autonomous/interactive split, the 8 seams as its interface set (absorb discipline, no vendor names). Binding layer records adopt-first: adopt the qualifying spine library as a build-stage dependency, re-verified at trigger time (maintenance, license, seam fit); reimplement-the-pattern is the named fallback on failed re-verification. |
| D3 | Isolation backends: the sandbox-provider seam is the normative requirement; the launch backend set derives from matrix coverage of trigger-admitted work — one free self-run L2 container-class backend (default-deny egress) at launch; an L3 backend is deferred with trigger = first C5-class work admitted to autonomous drain (fail-closed blocks C5 dispatch until an L3 binding exists); paid/cloud backends advisory + explicit opt-in. |
| D4 | Lifecycle: full state model in the contract — lease-claim → execute in isolation → verification gates (matrix column) → disposition per merge policy → escalate or complete, every transition emitting telemetry per the telemetry contract. Launch disposition is thin: per-item PR through the platform's native flow. Batched gated merge serialization is a named growth stage with an evidence trigger (observed concurrent auto-merge collisions), binding to a platform-native merge-queue facility where one exists (availability verified at binding time); never reimplement a built-in. |
| D5 | Escalation UX (WP5 D6 remainder, evidence: RESEARCH-escalation-observability.md): terminal-handoff at launch — every stop is a terminal state (success / gate-failed / needs-human / cap-exceeded); the runner files a human-gated work item carrying the evidence bundle (failure summary, run-transcript link, cost, trace link, session-resume handle; human takeover = resume the persisted session). Contract carries the two-family stop-criteria taxonomy: deterministic runner-owned (turn/budget/wall-clock caps, execution error after retries, refusal, verification-gate failure, isolation violation) and judgment agent-signaled through the structured-output envelope (ambiguity, design decision needing human judgment, security/data-integrity event, unresolvable blocker, no-progress); transient-recoverable retries with backoff, never escalates. Escalation event classes gain a severity axis mapped to org-bound notification fan-out (personal-push tier included as an org-bindable route); acknowledgment on the item + stale-unacked re-escalation (severity bump, capped) are org-bindable knobs. Mid-run interrupt (pause-for-human) deferred with trigger: evidence that kill-and-resume loses material cost/context; first-party pause/resume mechanisms verified available, so later adoption needs no contract change. Escalation telemetry rides the telemetry contract's custom namespace (no standard escalation signal exists; candidate upstream contribution). |
| D6 | Topology: ownership seams pre-committed, shape at birth. Design-pack docs stay in the capability-distribution home; at trigger fire the runner-execution home is born owning the runner implementation + its build/release toolchain, consuming the contract docs (never duplicating them). Security-sensitive runner bindings (level→substrate, merge policy, escalation routes, admission) live in the settings-as-code home — the runner reads its governance, never writes it (the agent-writable-binding bypass-channel rationale generalizes to the runner itself); non-security operational config is deployment-owned per the hosting stance. Repo count, name, and implementation language resolve at birth via the naming pass + the re-verified spine choice. Absent settings-as-code home in an adopting org: layered resolution + fail-closed on absent security binding applies; guided-setup names the compliant path. |
| D7 | Imports, all unchanged: T4 charter core (queue-contract split, both build triggers, self-run-primary substrate stance with hosted human-gate cap, anti-goals); WP4 D6 executor surface classes — the runner is one executor behind the invocation-adapter seam, adapters untouched on swap; WP5 matrix columns + admission decision-table + caps, promotion human-ratified / demotion automatic, L2+ fail-closed floor; WP6 routine-filed items drain through the same queue (no routine-special path); telemetry contract + trace propagation on every lifecycle transition; return-accounting capture hooks at the runner's task boundary; queue + lease reused from the work-item capability — no second claim mechanism; the 8 seams as the spine's interface set. |

### Constraints

- Any fleet repo or vendor name in normative contract text is a defect; vendor names appear
  only as marked examples and in binding docs.
- Zero build artifacts anywhere in the package: no code, no repo, no templates; no sentence
  that reads as a build commitment.
- One queue, one lease, one escalation channel (the queue itself); no second claim, dispatch,
  or escalation mechanism.
- Security-sensitive runner bindings never live where the runner (or the agents it runs) can
  edit them.
- Fail-closed everywhere: absent L2 substrate, absent security binding, unbound C5 work —
  block and name the compliant path, never degrade silently.
- No new cost by default; paid backends/surfaces advisory + explicit opt-in with cost
  surfaced.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before
  scale).

### Acceptance criteria

- Design pack delivers, in contract vocabulary only: spine shape + 8 seam specifications,
  lifecycle state model, two-family stop-criteria taxonomy, severity/ack/re-escalation knob
  set, launch backend derivation, topology seam map.
- Zero build artifacts; runner-execution home unborn; T4 build triggers restated verbatim;
  no build commitment anywhere in the text.
- WP5 D6's escalation-UX deferral — the last WP5-inherited cross-package deferral — is
  resolved by this package (mid-run interrupt stays deferred with its own evidence trigger;
  this pack resolves the inherited deferral, it does not claim nothing remains deferred).
- Research gaps carried visibly, not laundered: CI-action-class failure-reporting UNVERIFIED;
  cross-vendor agent-needs-human signaling (agent-protocol / agent-instruction-file guidance)
  UNVERIFIED; managed-agent event names drift between stream and webhook surfaces — bind
  exact names at build from live docs; the deprecated approval-SDK is never cited as living
  precedent.
- Boris check: step-3 trap honored (charter-not-build, trust before scale); the 2→3 "let
  Claude kick off Claude" cell stays inside the governed-queue audit trail; the step-4 cell
  is chartered, not built — closed loop via self-run substrate, programmatic-scheduling
  surface class, cost controls as caps/budget knobs, model selection as cost tiers;
  monitor-by-exception instantiated as terminal-handoff escalation; the thread-post return
  metric is fed by return-accounting capture at the runner boundary.

### Captured assumptions

- The qualifying spine library remains maintained and license-compatible at trigger time —
  re-verify at trigger; reimplement-the-pattern is the named fallback (D2).
- First-party pause/resume mechanisms (SDK callback pause + defer/resume, managed idled
  webhook) remain available — beta/moving surfaces; re-verify at build before relying on
  them for the mid-run-interrupt growth stage.
- The work-item capability's race-safe lease + autonomous drain mode remain the dispatch
  entrypoint (live-verified in a prior session).
- Personal-push notification routes presuppose org-bound channel adapters (WP4) at binding
  time; absent adapters, severity fan-out degrades to tracker-item-only — never silently
  drops the escalation itself.

### Out-of-scope (deferred with triggers)

- Runner build itself — trigger: either T4 build trigger fires.
- L3 backend — trigger: first C5-class work admitted to autonomous drain.
- Batched gated merge serialization — trigger: observed concurrent auto-merge collisions.
- Mid-run interrupt escalation — trigger: evidence that kill-and-resume loses material
  cost/context.
- Fleet materializations (runner stand-up, binding instances) — /work-items backlog
  post-graduation.

### Deferred questions

- Exact seam interface tokens, envelope field names, and lifecycle state tokens —
  `/architect` (with the plugin naming pass).
- Severity level names + default staleness window and re-escalation cap values —
  `/architect`.
- Setup/probe mechanics per backend class (joins the WP5 D4 slice) — `/architect`.
- Birth-time decisions: repo count/name/implementation language, spine re-verification
  outcome, exact managed-event name bindings — build stage, gated on the T4 trigger;
  **arbiter: USER-RESERVED** (trigger firing is a user-ratified event).

## Plan

Recommendation-locked this round under the user's standing pre-authorization. Token sets
(D-deferred, resolved here): lifecycle state tokens `leased` / `executing` / `verifying` /
`disposing` / `escalated` / `complete` (terminal: `escalated`, `complete`); terminal-outcome
tokens `success` / `gate-failed` / `needs-human` / `cap-exceeded`; stop-criteria family
tokens `runner-owned` (deterministic) and `agent-signaled` (judgment, via the
structured-output envelope field `stop_reason`); severity levels `notice` / `attention` /
`urgent` (three levels — mapped to org-bound notification fan-out; tracker item always,
channel notification per org route, personal-push tier org-bindable at `urgent`); default
staleness window 72h with one re-escalation (severity bump, cap 1) — org-bindable knobs.
Design-pack docs live under `reference/runner/` (hub `reference/runner.md`).

Prerequisites: WP4 + WP5 + WP6 implementation PRs merged (this pack imports their contracts
by citation). Design only — zero build artifacts; the runner-execution home stays unborn.

### Phase 1: Charter import + spine and seam specs [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/runner.md` | Create | Design-pack hub: T4 charter imported verbatim-in-substance (queue-contract split interactive-upstream / autonomous-downstream; BOTH build triggers restated verbatim; self-run-primary substrate stance with the hosted human-merge-gate cap; anti-goals) with an explicit no-build-commitment clause; the two-layer composition spine per D2 — normative spine SHAPE in seam vocabulary (minimal composable orchestration, pluggable sandbox-provider seam × pluggable agent-adapter seam, autonomous/interactive split) with the 8 seams as its interface set; adopt-first binding stance recorded (qualifying spine library re-verified at trigger time; reimplement-the-pattern the named fallback); glance rule routing depth to the leaves. |
| `plugins/autonomy/reference/runner/seams.md` | Create | The 8 seam specifications in contract vocabulary (invocation adapter, structured-output envelope, queue+lease, isolation policy, outcome-verification gate, merge-policy toggle, observability+cost, session/resume+caps): each seam's obligation set, its already-shipped owning contract where one exists (queue+lease → trigger-dispatch; isolation policy → guardrails; observability+cost → telemetry; capture at task boundary → return accounting) cited never restated, and the runner-side interface tokens. Envelope field names resolved: `stop_reason`, `outcome`, `evidence` (bundle ref), `resume_handle`. |

**Sanity Check:**

- `grep -ci 'build trigger' plugins/autonomy/reference/runner.md` ≥ 2 (both triggers restated)
- `grep -c 'no build' plugins/autonomy/reference/runner.md` ≥ 1 (commitment clause present)
- Seam count: `grep -cE '^## ' plugins/autonomy/reference/runner/seams.md` = 8
- Vendor+fleet deny-list sweep exit 0; lychee lane passes

### Phase 2: Lifecycle + stop-criteria + escalation leaves [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/runner/lifecycle.md` | Create | Full state model per D4: `leased → executing → verifying → disposing → (escalated | complete)`, every transition emitting telemetry per the telemetry contract (trace-linked); launch disposition thin (per-item PR through the platform's native flow, merge disposition governed by the WP5 matrix row — including the vendor-hosted human-gate cap whenever the executing backend is vendor-hosted, restated here rather than inherited silently); batched gated-merge serialization named as a growth stage with its evidence trigger (observed concurrent auto-merge collisions) binding to a platform-native merge-queue facility — never reimplemented. |
| `plugins/autonomy/reference/runner/escalation.md` | Create | D5 resolved: terminal-handoff at launch — every stop terminal (`success`/`gate-failed`/`needs-human`/`cap-exceeded`); the runner files a human-gated work item with the evidence bundle (failure summary, run-transcript link, cost, trace link, `resume_handle`; human takeover = resume the persisted session); two-family stop-criteria taxonomy verbatim (runner-owned: turn/budget/wall-clock caps, execution error after retries, refusal, verification-gate failure, isolation violation; agent-signaled via `stop_reason`: ambiguity, design decision, security/data-integrity event, unresolvable blocker, no-progress); transient-recoverable retries with backoff, never escalates; severity axis (`notice`/`attention`/`urgent`) → org-bound fan-out with personal-push as an org-bindable route; acknowledgment-on-item + stale-unacked re-escalation (default 72h window, one severity-bump re-escalation, both org-bindable); mid-run interrupt deferred with its evidence trigger; escalation telemetry rides the telemetry contract's custom-namespace mechanism — the exact namespace token is read from the shipped telemetry contract at implementation, not pinned here (candidate upstream contribution noted). Research gaps carried verbatim (CI-action-class failure-reporting UNVERIFIED; cross-vendor needs-human signaling UNVERIFIED; managed-agent event-name drift — bind at build; deprecated approval-SDK never cited as living precedent). |
| `plugins/autonomy/reference/runner/topology.md` | Create | D6: ownership seam map — design pack in the capability-distribution home; at trigger fire the runner-execution home is born owning implementation + build/release toolchain, consuming contracts never duplicating; security-sensitive runner bindings in the settings-as-code home (runner reads its governance, never writes it); non-security operational config deployment-owned; launch backend set per D3 (one free self-run L2 container-class backend; L3 deferred with the first-C5 trigger, fail-closed until bound — the C5→L3 floor CITED from the WP5 work-classes matrix cell, never asserted independently here, per stress-test F5; paid/cloud advisory + opt-in, and any cloud backend IS a vendor-hosted executor: it forces the security binding's `executor_class: vendor-hosted`, capping every merge row at human-gated, per F6); birth-time decisions listed with arbiter USER-RESERVED (repo count/name/language, spine re-verification, exact managed-event names). |

**Sanity Check:**

- State tokens present: `grep -c 'disposing' plugins/autonomy/reference/runner/lifecycle.md` ≥ 1
- `grep -c 'cap-exceeded' plugins/autonomy/reference/runner/escalation.md` ≥ 1 and `grep -c 'stop_reason' …/escalation.md` ≥ 1
- `grep -ci 'UNVERIFIED' plugins/autonomy/reference/runner/escalation.md` ≥ 2
- `grep -c 'USER-RESERVED' plugins/autonomy/reference/runner/topology.md` ≥ 1
- Vendor+fleet deny-list sweep exit 0

### Phase 3: Setup note + WP5 escalation-route join [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | A short runner note only: the design pack is bindable-when-born; setup records NOTHING runner-specific until the trigger fires except escalation notification routes (severity axis + personal-push tier as route options). No probe, no wiring, no binding section for the unborn home. |
| `plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` | Modify | The severity refinement is GENUINELY additive (stress-test F2 — the schema is `additionalProperties: false`, so an undeclared shape would fail every severity-tiered binding): `escalation_routes` keeps its existing event-class→route entries unchanged; three new OPTIONAL top-level keys land beside it, modeling the event/severity join explicitly — `escalation_severity` (event class → severity token, the join: which severity each event class escalates at; contract defaults per event class, org-bindable), `escalation_severity_routes` (severity token → route, `notice`/`attention`/`urgent`, personal-push a legal route value at any tier; route resolution = event class → its severity → that severity's route, falling back to the event class's own `escalation_routes` entry when no severity route is bound), and `escalation_ack` (`staleness_window`, default 72h; `reescalation_cap`, default 1). Old bindings validate unchanged — no major bump; that resolution is now in-plan, not asserted. |
| `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` | Modify | Semantic checks for the new keys: severity tokens ∈ the three-level set; `escalation_ack` values positive; every event class keyed in `escalation_severity` must exist in `escalation_routes` (the join makes this check implementable — an unroutable event class is flagged); a bound severity in `escalation_severity` with no `escalation_severity_routes` entry AND no event-class fallback route flagged. |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Escalation-route slice case (severity + personal-push binding recorded; unborn-home refusal restated) — stress-test F7: every other WP adds eval coverage for its SKILL.md change; no exemption here. |
| `plugins/autonomy/README.md` + `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Capability list gains the runner design pack; the roadmap row stays trigger-gated (build), now pointing at the pack; minor version bump. |

**Sanity Check:**

- `grep -ci 'unborn' plugins/autonomy/skills/setup/SKILL.md` ≥ 1
- README roadmap still carries the build trigger row (`grep -c 'build trigger' plugins/autonomy/README.md` ≥ 1)
- Schema additivity: `grep -c 'escalation_severity_routes' …schema.json` ≥ 1 and a pre-WP7 fixture binding still passes `check-security-binding.mjs` unchanged (no major bump proven, not asserted)
- `/skill-quality:check` + `validate-evals` pass; `claude plugin validate --strict` exit 0

### Phase 4: Zero-build audit + gates [TODO]

Acceptance probe (mechanical): the package introduces no executable/runtime artifact — the
diff contains no new files outside `reference/`, `skills/setup/`, README, and plugin
manifest; no new scripts; no repo-creation instruction anywhere. Then the full gate roster
(`validate-plugins.sh`, `run-plugin-tests.sh`, `validate-plugin-contracts.mjs`,
markdown/typos/lychee, `claude plugin validate --strict`, catalog regen). Near-duplicate
audit statement: the pack cites the shipped contracts for every inherited obligation and
defines only runner-new content.

**Sanity Check:**

- `git diff --name-only <base>` contains no path outside the four allowed surfaces; no `*.sh`/`*.mjs` additions
- `grep -rci 'git init\|create the repo' plugins/autonomy/reference/runner*` = 0
- All gate scripts exit 0; catalog in-sync; near-duplicate audit statement in the PR body

## Blast radius

MEDIUM — docs-only within one plugin, but the pack pre-commits topology and escalation
contracts the eventual build must honor; WP5's last cross-package deferral resolves here.
Fully git-revertible; zero runtime surface by design.

## Stress-test summary

Fresh-context plan review (WP6+WP7 batch): 10 findings, verdict FIX-THEN-SHIP, WP7's share
folded — F2 (HIGH): the escalation-route severity refinement touched the WP5 security-binding
schema (`additionalProperties: false`) but Phase 3 listed neither the schema nor the
validator, leaving the flagship severity/ack knob set unbindable, and "additive, no major
bump" was asserted over what read as a value-shape change → both files added to Phase 3 and
the refinement modeled as genuinely additive optional keys (`escalation_severity_routes`,
`escalation_ack`), with a pre-WP7 fixture-passes gate proving no major bump. F5 (MED): the
C5→L3 fail-closed gate now CITES the WP5 work-classes matrix cell (which imports T3's C5/L3
row) instead of asserting the value. F6 (LOW-MED): the vendor-hosted human-gate merge cap is
restated on the cloud-backend and disposition paths instead of silently inherited. F7 (LOW):
the Phase 3 SKILL.md change gains eval coverage like every other WP. F9 (LOW): the
"last cross-package deferral" claim scoped to the WP5-inherited deferral. F10 (LOW): the
escalation-telemetry namespace token is read from the shipped telemetry contract at
implementation, not pinned in the plan. Scope discipline (zero build artifacts, unborn
runner-execution home, USER-RESERVED birth decisions) audited clean.

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — leaves depend on the hub's imported charter; the setup note
cites Phase 2's escalation severity axis; Phase 4 audits the authored tree. Cross-package:
after WP4+WP5+WP6 implementation PRs.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | charter import fidelity + seam-spec judgment |
| 2 | main-session | lifecycle/escalation normative authoring |
| 3 | main-session | minimal setup-skill touch |
| 4 | main-session | mechanical audit + gate runs |

## Open questions

- Birth-time decisions (repo count/name/language, spine re-verification, managed-event
  names) — USER-RESERVED at trigger fire, restated in topology.md.

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Lifecycle tokens `leased/executing/verifying/disposing/escalated/complete` | Phase 2 leaf | D4's state model named each stage; kebab/lowercase matches shipped token sets |
| Terminal outcomes `success/gate-failed/needs-human/cap-exceeded` | Phase 2 leaf | D5 names exactly these four |
| Severity set `notice/attention/urgent`; 72h staleness, one re-escalation | Phase 2 leaf | D5 requires a severity axis + ack/re-escalation knobs with suggested defaults; three tiers is the smallest set covering tracker-only / channel / push fan-out |
| Envelope fields `stop_reason/outcome/evidence/resume_handle` | Phases 1–2 | D5's evidence-bundle + resume requirements; smallest field set carrying them |
| Hub-and-leaves under `reference/runner/` | Phase 1–2 paths | Same layout as WP5/WP6 hubs |
| Escalation-route severity refinement = new OPTIONAL schema keys (`escalation_severity` as the explicit event→severity join, `escalation_severity_routes`, `escalation_ack`) beside an untouched `escalation_routes`; schema + validator edits in Phase 3 | Phase 3 | WP5 D6 routes live there; stress-test F2 — only genuinely additive keys avoid a major bump under `additionalProperties: false`, proven by the pre-WP7 fixture gate; the join key answers the PR-review finding that severity→route alone left route selection non-deterministic per event class |

## Handoff to implementation

### User-approval gates

- Anything that reads as a build commitment or creates a runtime artifact → STOP (D1
  user-locked; the zero-build audit is the backstop).
- Birth-time decisions stay USER-RESERVED — never resolved by implementation.
- Any scope expansion beyond the four phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same
commit as each phase.

### Mechanical work

Commit per phase on the implementation branch (suggest `docs/autonomy-runner-design-pack` —
docs-type: the package is normative text only); gates re-run in full at Phase 4; PR body
carries the zero-build audit output + near-duplicate audit statement + this PLAN in a
`<details>` block at close-out.
