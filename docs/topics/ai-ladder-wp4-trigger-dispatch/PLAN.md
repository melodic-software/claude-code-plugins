# ai-ladder-wp4-trigger-dispatch

## Brief

### TLDR

Trigger-dispatch package (T1): a contract doc for signal adapters and dispatch, plus the
trigger/dispatch slice of guided-setup. Adapters normalize signals from four surface classes
into the governed work-item queue; one dispatch entrypoint drains it; the executor is
swappable behind the invocation-adapter seam.

### Goal

Any adopting org can wire its signal surfaces into the governed queue and get autonomous
dispatch without a human kick — contract vocabulary only, free by default, audit trail
intact end to end.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Scope: contract doc + trigger/dispatch slice of guided-setup, both in the capability-distribution home. Fleet adapter materializations = /work-items backlog. |
| D2 | Four signal-surface classes, ALL contract-active: tracker/VCS-host events (label, assignment, @-mention, PR event); temporal (schedule + poll-fallback detectors for push-less surfaces); agent-internal (session emits follow-up work); channel/data-feed (chat mention + continuous monitor). Surface determines adapter home (WP1 D3 role split per class). Per-org availability is a binding outcome — no entitlement → advisory path per WP1 D6 — never a contract deferral. Exact class tokens at architect naming pass. |
| D3 | Two recorded attributes on every queued signal: initiator provenance (human / agent / system — audit + guardrail-matrix input; recorded, never trusted as an isolation axis per T2) and transport (PUSH / PUSH-WITH-LIFECYCLE / POLL; push preferred where the surface offers it, poll is the universal fallback via the temporal class; lifecycle variant carries subscription expiry + renewal + validation handshake). |
| D4 | Six class-generic adapter obligations: (1) normalize + enqueue only — never execute, no queue bypass; (2) idempotent dedup — key from signal identity, at-least-once delivery is universal on push surfaces; (3) provenance capture + durable raw-signal link on the item; (4) trace-context propagation — one causal tree trigger → CI → agent session (T6 import); (5) admission enforcement at the seam — policy content owned by the guardrail matrix (T3), binding owned by the settings-as-code home; the adapter enforces, never defines; unadmitted → human-gated item or audited rejection; (6) closed-loop acknowledgment — bidirectional surfaces echo the item reference back (tracker comment, chat thread reply); reply-less surfaces satisfy via the provenance link alone. |
| D5 | Dispatch: push kick where the platform offers it (e.g. a CI job fired by the enqueue event) + a standing scheduled drain as universal fallback and catch-up net. One-entrypoint invariant: every kick funnels into the existing autonomous drain mode of the work-item queue capability via the invocation-adapter seam; the race-safe lease makes concurrent kicks harmless. Concurrency and per-run item caps are guardrail-matrix policy knobs. Executor hosting (in-CI vs drain-elsewhere) is a deployment-owned binding per the T7 hosting stance — the contract fixes only invariants (isolation floor L2+, credential scoping, queue contract); guided-setup surfaces the compute/credential tradeoff per org. |
| D6 | Executor surface classes imported from T4 unchanged: self-operated CLI/SDK — including SDK-embedded pull/drain daemons (Boris step-4 products cell names the vendor agent SDK for programmatic scheduling; cross-vendor equivalents exist) — vs vendor-hosted, whose merge policy caps at human-gated. The CI-action-class automation mode (arbitrary prompt on any workflow event) is live-verified. |
| D7 | Guided-setup slice is discovery-first (WP1 D7): interview the adopting org for which surfaces exist, transport capability per surface, and entitlements; wire the DIY floor (chat-platform bot + events subscription, or plain inbound webhook) as reviewable changes; advise plan-gated native integrations with cost surfaced; bind admission policy; set up kick + drain. |

### Constraints

- Any fleet repo or vendor name in normative contract text is a defect; vendor names appear
  only as marked examples and in binding docs.
- One queue, one lease, one dispatch entrypoint — no second claim or dispatch mechanism
  anywhere in the package.
- No new cost by default; paid surfaces are advisory + explicit opt-in with cost surfaced.
- The contract never invents an event bus and never raises domain events — the adopting
  org's own systems own event definition and raising.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before
  scale).

### Acceptance criteria

- Contract doc names the four surface classes, six adapter obligations, three-value
  transport enum, and kick + drain dispatch spec — in contract vocabulary only.
- Guided-setup slice is discovery-first, wires only reviewable changes, advises gated
  surfaces with cost, and has zero paid dependencies on its default path.
- No queue bypass or second dispatch mechanism exists anywhere in the package.
- Research gaps are carried visibly, not laundered: channel-monitor ambient
  initiate-vs-notify UNVERIFIED; the two channel-agent vendor surfaces relied on are
  alpha/beta moving targets; no first-party Discord trigger found (UNVERIFIED-absence).
- Boris check: the 2→3 cell ("break up your work into loops and routines; let Claude kick
  off Claude") is instantiated as governed queue + kick; the step-3 trap is honored (audit
  trail before scale, no agent-count machinery); the step-1 guardrail is untouched; the T6
  trace tree is the kick-off audit trail.

### Captured assumptions

- The work-item queue capability's autonomous drain mode + seam lease remain the dispatch
  entrypoint (live-verified against the installed capability this session).
- The CI-action-class executor supports arbitrary-prompt automation runs on schedule, label,
  and manual-dispatch events (official README fetched this session).
- Vendor channel integrations remain plan-gated and the DIY floor remains free
  (RESEARCH-channel-adapters.md, Jul 2026; flagged as moving targets).

### Out-of-scope (deferred with triggers)

- Runner build — trigger: T4 build trigger fires (WP7 owns the design pack).
- Fleet adapter materializations (reusable workflows, labels, drain-routine stand-up) —
  /work-items backlog post-graduation.
- Routine definitions for the v1 catalog — WP6.
- Dispatch POLICY content (which classes auto-dispatch, per-class gates) — WP5 (guardrail
  matrix instance).

### Deferred questions

- Exact class/attribute tokens + signal schema — `/architect` (with the plugin naming pass).
- Adapter template shapes per surface class + per-vendor binding docs — `/architect`.
- Acknowledgment/reply-back template wording — `/architect`.
- Drain cadence defaults + cap values — `/architect`.

## Plan

(unfilled — /architect)
