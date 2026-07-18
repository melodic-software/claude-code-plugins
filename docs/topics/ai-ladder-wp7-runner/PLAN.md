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
- WP5 D6's escalation-UX deferral is resolved by this package (the last cross-package
  deferral).
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

(unfilled — /architect)
