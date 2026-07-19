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

Recommendation-locked this round under the user's standing pre-authorization (same basis as
the WP2/WP3 round): surface-class tokens `tracker-vcs-event` / `temporal` / `agent-internal` /
`channel-feed`; transport enum `push` / `push-lifecycle` / `poll`; provenance enum `human` /
`agent` / `system`; signal envelope = a JSON-fenced marker record on the queued item (the WP3
marker-record precedent), keys `signal.class`, `signal.transport`, `signal.provenance`,
`signal.identity`, `signal.raw_link`, `signal.traceparent`, plus optional `signal.work_class`
(the T3 risk class the adapter STAMPS from the security-surface classification rules — see
Phase 1 (3bis); absent = unclassified = fail-closed human-gated) and `signal.parent_item`
(REQUIRED when `signal.class` is `agent-internal`: the canonical URL of the emitting
session's admitted source item — the machine-verifiable provenance the stamped class is
checked against; a stamped class is never trusted on its own) and `signal.source_surface`
(REQUIRED when `signal.class` is `temporal`: the originating scheduling surface's id as
recorded in the `triggers` binding — the discriminator raw-link form validation branches
on, since `temporal` alone spans both CI-cron and local-scheduler surfaces).

Authoring constraint (cross-package link hygiene): this package merges before WP5, so
normative text references the admission seam and classification rules by contract CONCEPT
only — never a file link to a not-yet-existing guardrail doc; WP5 adds the file cross-links
back to the then-existing `trigger-dispatch.md`.

Prerequisite: WP2 telemetry PR merged (`reference/telemetry.md` exists — this contract imports
its trace-tree obligation) and WP3 PR merged (marker-record precedent + return-accounting
capture rides the same close boundary the dispatch drain crosses). Implementation ordering
with WP5: this package's PR merges FIRST; admission enforcement here fail-closes when no
admission binding exists (absent policy → every dispatch human-gated), and WP5 then ships the
policy surface that relaxes it — no dead link in either direction, no dispatch window ever
runs ungoverned.

### Phase 1: Trigger-dispatch contract doc [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/trigger-dispatch.md` | Create | The T1 contract as tool-agnostic normative text. (1) Four signal-surface classes with tokens `tracker-vcs-event` (tracker/VCS-host events: label, assignment, @-mention, PR event), `temporal` (schedule + poll-fallback detectors), `agent-internal` (a session emits follow-up work), `channel-feed` (chat mention + continuous monitor) — ALL contract-active; per-org availability is a binding outcome, entitlement gaps route to the advisory path (WP1 D6), never a contract deferral; carried research gaps stated in SURFACE-CLASS vocabulary in this doc (channel-monitor ambient initiate-vs-notify UNVERIFIED; the relied-on channel-agent vendor surfaces are alpha/beta moving targets; one major chat platform has no first-party trigger, UNVERIFIED-absence) — vendor names for these gaps live in SKILL.md only, per the contract validator's vendor deny-list. (2) Two recorded signal attributes: initiator provenance (`human`/`agent`/`system` — audit + guardrail input, recorded never trusted as isolation, per T2) and transport (`push`/`push-lifecycle`/`poll`; push preferred where offered, poll universal fallback via `temporal`; `push-lifecycle` carries subscription expiry + renewal + validation handshake obligations, and EXPIRY semantics are normative: every `push-lifecycle` wiring is backed by a `temporal` poll-detector backstop for the same surface, or the subscription-health lapse fail-closes — files a human-gated alert item — so a lapsed subscription can never silently drop signals). (3) Six class-generic adapter obligations imported from the Brief D4 verbatim: normalize+enqueue only; idempotent dedup keyed on `signal.identity` (surface-native unique event id where the surface issues one; the FALLBACK identity is never a bare content hash — it composes source scope (surface class + origin locator) + an event-instance discriminator (delivery id or event timestamp) + the content hash, so two legitimate repeated signals with identical payloads stay distinct instances; for state-based poll detectors that re-observe a continuing condition and have no instance identity, dedup retention is BOUNDED to items still open — the same finding may re-enqueue once its prior item closes (a re-detected regression is a new signal). Dedup enforcement is NOT a bare read-then-write: concurrent at-least-once deliveries can both pass a search before either item exists, so the adapter uses an atomic identity-keyed create/upsert or queue-side uniqueness guarantee where the tracker offers one; where none exists, search-before-create is backed by CREATE-THEN-RECONCILE — after creating, re-search by `signal.identity` and, on finding an older item with the same identity, close the newer one as an audited duplicate (oldest wins, deterministic) — plus a drain-side guard scoped to LIVE duplicates only: the drain never claims an item whose `signal.identity` matches another currently-open item (claimed or awaiting reconciliation) — completed items are excluded from the guard, consistent with the bounded-retention rule, so a fixed-then-regressed condition re-enqueues AND executes, while an unreconciled concurrent twin still cannot run the same work twice); provenance capture + durable `signal.raw_link`; trace-context propagation (`signal.traceparent`, one causal tree per the telemetry contract); admission enforcement at the seam (policy content owned by the guardrail matrix; the adapter enforces, never defines; unadmitted → human-gated item or audited rejection; ABSENT admission binding → fail-closed: enqueue human-gated, never drop silently); closed-loop acknowledgment (bidirectional surfaces echo the item reference back; reply-less surfaces satisfy via `signal.raw_link` alone). (3bis) Work-class classification obligation: admission and the whole guardrail matrix key on the T3 risk class, so a queued item needs one — the adapter STAMPS `signal.work_class` from the classification rules on the org's SECURITY governance surface (owned by the guardrail contract; the adapter stamps, never defines): tracker-vcs-event resolves via the security-bound label→class rules; temporal signals carry the class their bound routine/detector definition derives; agent-internal items must PROVE protected provenance — the envelope SERIALIZES the emitting session's own admitted source item as `signal.parent_item` (required for this class), and the admission seam VERIFIES the session-to-parent association against protected dispatch data (the queue's own lease/claim record of which item the emitting session was dispatched on — an agent-supplied URL alone proves nothing: any session could cite an unrelated C1 item to launder higher-risk follow-up work); an association the seam cannot verify is treated as NO provenance (unclassified, fail-closed human-gated). Admission then RESOLVES the verified parent's class from its own protected classification rather than trusting the stamped value: the effective class is the HIGHER of that inherited class and the class the security-surface rules derive for the target — a session never self-assigns a lower class for its follow-up work (self-classification would bypass admission: stamp C1 on C4 work and the table admits it); an agent-internal signal that cannot prove that provenance stays UNCLASSIFIED (recorded with `agent` provenance, admission-checked like any input); channel-feed and any signal the rules cannot resolve stay UNCLASSIFIED → fail-closed human-gated. No repo-local (agent-writable) surface may supply the class used for admission. (4) Signal envelope serialization: JSON-fenced marker record on the queued item, the six required `signal.*` keys plus optional `signal.work_class`, `schema_version` from `"1.0"` — additive evolution, same governance as every contract schema. (5) Dispatch spec: push kick where the platform offers it + a standing scheduled drain as universal fallback and catch-up net for ENQUEUED items (default cadence hourly, org-bindable; the drain never re-scans a source surface — missed enqueues are the poll-detector backstop's job per (2)); one-entrypoint invariant — every kick funnels into the work-item queue capability's autonomous drain mode via the invocation-adapter seam; the race-safe lease makes concurrent kicks harmless; concurrency and per-run caps are guardrail-policy knobs — named descriptively here, serialized tokens (`autonomous_concurrency`, `items_per_run`) owned by the admission policy. (6) Executor surface classes imported from T4 unchanged (self-operated CLI/SDK incl. SDK-embedded pull daemons vs vendor-hosted with human-merge-gate cap); the executor-class determination that gates merge policy is SECURITY-surface data (the guardrail binding's `executor_class`), never a repo-local value; other executor hosting config stays deployment-owned (T7 stance) — contract fixes isolation floor L2+, credential scoping, queue contract only. Constraints restated normatively: no queue bypass, no second dispatch mechanism, no invented event bus, no new cost by default, vendor names only as marked examples. |

**Sanity Check:**

- `grep -c 'tracker-vcs-event' plugins/autonomy/reference/trigger-dispatch.md` ≥ 1 and same for `temporal`, `agent-internal`, `channel-feed`
- `grep -c 'push-lifecycle' plugins/autonomy/reference/trigger-dispatch.md` ≥ 1 and expiry backstop stated (`grep -c 'poll-detector' …/trigger-dispatch.md` ≥ 1)
- `grep -c 'signal.identity' plugins/autonomy/reference/trigger-dispatch.md` ≥ 1, `grep -c 'signal.work_class' …/trigger-dispatch.md` ≥ 1, and `grep -c 'signal.parent_item' …/trigger-dispatch.md` ≥ 1
- `grep -ci 'fail-closed' plugins/autonomy/reference/trigger-dispatch.md` ≥ 2 (absent-admission AND unclassified behavior stated)
- `grep -ci 'UNVERIFIED' plugins/autonomy/reference/trigger-dispatch.md` ≥ 2 (research gaps carried in surface-class vocabulary, not laundered)
- No forward file-link to a guardrail doc: `grep -c 'guardrails' plugins/autonomy/reference/trigger-dispatch.md` counts concept references only — `grep -cE '\]\((\./)?(guardrails|.*guardrails/.*)\.md' …/trigger-dispatch.md` = 0
- Vendor+fleet deny-list grep empty over the doc (`node scripts/validate-plugin-contracts.mjs` exit 0)
- lychee lane passes

### Phase 2: Guided-setup trigger/dispatch slice [DONE]

Extends the `setup` skill (discovery-first per D7/WP1 D7). First work item — fresh-docs
mandate (repo CLAUDE.md): re-fetch the official docs for any vendor surface the slice names
(CI events, schedule syntax, headless invocation) before editing SKILL.md.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Add the trigger/dispatch slice to discovery + apply: interview which signal surfaces exist per class, transport capability per surface, entitlements; wire the DIY floor as reviewable changes (platform event kick + scheduled drain; chat-platform bot or plain inbound webhook for `channel-feed` where wanted); advise plan-gated native integrations with cost surfaced; bind the drain (cadence default hourly, org override recorded); EVERY kick/drain wiring records its named execution surface — the same surface id the guardrail security binding's per-surface isolation entries key on — but the RECORDED id is repo-local (agent-writable) convenience only: the admission/executor seam derives the ACTUAL execution-surface identity from trusted dispatch/runner context (platform-attested runtime metadata, matched against per-surface identifying markers the SECURITY binding's isolation entries declare) and verifies it against the recorded id, consulting the ACTUAL surface's isolation verdict — a mismatch, an unattestable actual surface, or a surface with no L2 binding all fail-close to human-gated, so rewriting the recorded id to a bound sibling cannot launder execution onto an unbound runner; record the trigger binding as an ADDITIVE `triggers` section of the WP1 schema-versioned binding (absent-section tolerance; no major bump). Admission enforcement wiring points at the guardrail admission seam and states the fail-closed absent-binding behavior. All vendor env vars/event names live here, never in `reference/`. |
| `plugins/autonomy/skills/setup/templates/trigger-adapters.md` | Create | Adapter snippet templates per surface class, surface-class-parameterized, fleet names banned: tracker-vcs-event (label/assignment event → enqueue step shape), temporal (scheduled drain + poll-detector shape), agent-internal (session files follow-up via the queue seam), channel-feed (webhook receiver → enqueue shape). Each template carries the six adapter obligations inline (dedup key derivation, raw-link capture, traceparent injection, ack echo). |
| `plugins/autonomy/skills/setup/templates/ack-reply.md` | Create | Acknowledgment template wording for bidirectional surfaces: `Queued as <item-url> (autonomy: <class> signal)` — one line, item URL first (the join key), class token for audit; reply-less surfaces documented as satisfied by `signal.raw_link`. |
| `plugins/autonomy/skills/setup/scripts/check-signal-envelope.mjs` | Create | Enforcement surface for the envelope: validates a queued item's JSON-fenced `signal.*` marker record — six required keys present, enum values legal (incl. `signal.work_class` ∈ C1–C5 when present), `signal.parent_item` REQUIRED (well-formed absolute https URL) whenever `signal.class` is `agent-internal` — its absence fails validation, since an unverifiable self-stamped class would bypass admission; the class-resolution itself (inherited-vs-derived max) is the admission seam's job at dispatch time, the checker enforces the serialized provenance it needs — the ITEM URL normalized per the telemetry contract's strip rule, `signal.raw_link` validated as a DURABLE absolute reference, form branched DETERMINISTICALLY by serialized origin: the checker takes the schema-versioned binding as an input and resolves `signal.source_surface` against BOTH its additive sections that record scheduling surfaces — `triggers` (kick/drain wiring) and `routines` (each routine's recorded scheduler/surface choice), since routine signal producers record their surface in the latter, not as trigger entries — a temporal signal whose source surface the binding records as local-scheduler class may carry a durable local/artifact URI (an absolute `file:` URI or org artifact-store locator — such surfaces have no web origin); every other signal (including temporal from CI-cron or any remote surface) requires a well-formed absolute https URL (query/fragment PRESERVED — comment anchors and permalinks need them; the strip rule is the join key's, not the raw link's); a temporal signal missing `signal.source_surface`, or naming a surface the binding does not record, fails validation; relative or ephemeral references fail either branch, `schema_version` known. Mirrors `check-emission-conformance.mjs` (same exit contract 0/1/2). |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Add trigger-slice cases: surface discovery interview path, DIY-floor wiring, plan-gated advisory refusal-to-default, absent-admission fail-closed statement, non-interactive argument-supplied run. |
| `plugins/autonomy/README.md` | Modify | Shipped-capability list grows by the trigger-dispatch contract + setup slice. |
| `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Description extends; minor version bump. |

**Sanity Check:**

- `/skill-quality:check` + `validate-evals` pass (`skills_root` = `plugins/autonomy/skills`)
- `claude plugin validate --strict` exit 0
- `grep -c 'signal.identity' plugins/autonomy/skills/setup/templates/trigger-adapters.md` ≥ 1
- `node plugins/autonomy/skills/setup/scripts/check-signal-envelope.mjs` (no args) exits 2 with usage
- Fleet-name sweep (`validate-plugin-contracts.mjs`) exit 0

### Phase 3: Conforming-path demonstration [DONE]

Acceptance probe on a scratch consumer repo (NOT this repo, WP2 Phase 3 precedent — the ban
there is on FLEET bindings/plugins, not on composing a sibling CAPABILITY: the scratch repo
INSTALLS the work-items capability plugin, whose queue + race-safe lease IS the seam under
demonstration; stubbing the lease would weaken the one-entrypoint proof to nothing): a
tracker-vcs-event stub (label applied) runs the adapter shape → item lands in the governed
queue carrying the full signal envelope + ack echo on the source surface; the scheduled-drain
entrypoint claims it via the seam lease (autonomous drain mode) — demonstrating kick + drain
funneling into ONE entrypoint; TRACEPARENT from the trigger hop is observed on the enqueue
record (telemetry-contract import). `check-signal-envelope.mjs` passes against the created
item. Absent-admission fail-closed is demonstrated live: with no admission binding present,
the drained item is refused autonomous execution and remains human-gated, with the refusal
audited on the item (this also exercises the unclassified → human-gated path: no security
binding means no classification rules, so the item carries no `signal.work_class`).

**Sanity Check:**

- The scratch item body contains a valid `signal.*` marker record (`check-signal-envelope.mjs` exit 0)
- The ack comment on the source surface contains the item URL
- Drain transcript shows the seam lease claim and the fail-closed human-gated refusal (no admission binding)
- No second dispatch path exercised anywhere in the demo; no paid service touched
- Demo transcript attached to the PR body

### Phase 4: Gates [TODO]

Full in-repo gate run (WP2 Phase 4 roster): `scripts/validate-plugins.sh`,
`scripts/run-plugin-tests.sh`, `node scripts/validate-plugin-contracts.mjs`, markdown/typos/
lychee lanes, `claude plugin validate --strict`, catalog regen check. Near-duplicate audit
statement: the dispatch entrypoint composes the work-item queue capability's existing
autonomous drain — no second claim/dispatch mechanism was created.

**Sanity Check:**

- All gate scripts exit 0
- `node scripts/generate-catalog.mjs` reports in-sync
- Near-duplicate audit statement present in the PR body

## Blast radius

MEDIUM — one plugin's files, but the contract constrains WP5/WP6/WP7, every future adopter,
and the admission seam WP5 binds to; new convention + cross-package coupling triggers match.
Fully git-revertible; automated gates cover shared surfaces.

## Stress-test summary

Fresh-context plan review (WP4+WP5 batch): 14 findings, verdict FIX-THEN-SHIP, all folded.
WP4's share — F1a (HIGH, cross-package): the envelope carried no T3 work class, leaving the
autonomous happy-path non-functional (safe but dead) → `signal.work_class` + the (3bis)
classification obligation, class source pinned to the security surface; F2 (HIGH): verbatim
vendor names in reference/ collide with the contract validator's vendor deny-list →
surface-class vocabulary in reference/, vendor specifics in SKILL.md; F3 (MED-HIGH): the
telemetry strip rule misapplied to `signal.raw_link` would corrupt durable event links →
strip rule confined to the item URL; F4 (MED): push-lifecycle expiry had no fail-closed
semantics → poll-detector backstop / fail-closed lapse, and the drain's no-rescan limit
stated; F5 (MED): the Phase 3 seam demo now explicitly installs the work-items capability
(sibling capability ≠ banned fleet binding); F6 (MED, latent): forward file-links to
not-yet-existing guardrail docs → concept-only references, WP5 back-links; F7 (LOW): cap
knob token ownership pinned to the admission policy's serialized names. F8 (LOW) accepted:
the no-second-dispatch and Boris checks stay prose PR-body audits, consistent with the
WP2/WP3 round.

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — Phase 2 cites Phase 1's contract; Phase 3 exercises Phase 2's
templates and check script; Phase 4 gates the tree. Cross-package: this PR merges before the
WP5 implementation PR (WP5's admission policy binds the seam this contract defines; the
fail-closed absent-binding clause makes the interim safe).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | normative contract authoring, tightly coupled to T1/T4/T7 imports |
| 2 | main-session | setup-skill + template judgment, vendor-doc re-fetch gate |
| 3 | main-session | scratch-repo runtime probe with divergence judgment |
| 4 | main-session | gate runs |

## Open questions

- Fleet adapter materializations (reusable workflows, labels, drain-routine stand-up) —
  /work-items backlog post-merge (Brief out-of-scope, trigger recorded).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Surface-class tokens `tracker-vcs-event`/`temporal`/`agent-internal`/`channel-feed` | Phase 1 contract vocabulary | Brief D2 class descriptions; kebab-case matches every shipped contract token set |
| Transport tokens `push`/`push-lifecycle`/`poll` | Phase 1 enum | Brief D3 three-value enum; `push-lifecycle` compresses PUSH-WITH-LIFECYCLE without semantic loss |
| Signal envelope = JSON-fenced marker record, `signal.*` keys, `schema_version` "1.0" | Phase 1 serialization + Phase 2 check script | WP3 marker-record precedent (tracker-resident, adapter-written, queryable) |
| Drain cadence default hourly, org-bindable | Phase 1 dispatch spec + Phase 2 slice | Universal catch-up net with bounded token cost; value is a binding knob, not contract |
| Cap VALUES deferred to the WP5 admission policy; WP4 names the knobs | Phase 1 dispatch spec | Brief D5 assigns caps to guardrail policy; avoids double ownership |
| WP4 merges before WP5; absent admission binding fail-closes to human-gated | Plan preamble + Phase 3 demo | Brief D4 obligation 5 (enforce, never define) + no-ungoverned-window requirement |
| `signal.work_class` optional envelope key + security-surface classification obligation; unclassified → human-gated | Phase 1 (3bis) + Phase 2 check | Stress-test F1a: the matrix and admission key on C1–C5, which no trigger path assigned; agent-writable class sources are a bypass channel |
| Executor-class merge gating reads the security binding's `executor_class`, never repo-local data | Phase 1 (6) | Stress-test F1b: hosted human-merge-gate cap must not be flippable from inside the blast radius |

[FALLBACK — confirm or override] `check-signal-envelope.mjs` as a NEW deliverable (Phase 2) —
invented beyond the Brief on the WP2 precedent (a pinned contract with no enforcement surface
is undetectable drift). Flag if unwanted.

## Handoff to implementation

### User-approval gates

- The envelope-check script above is [FALLBACK] — surface before authoring if contested.
- If the platform's event kick cannot reach the drain entrypoint without a second dispatch
  path, STOP and re-surface — the one-entrypoint invariant is non-negotiable.
- Any scope expansion beyond the four phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same commit
as each phase; scratch-repo demo per Phase 3; divergence escalation applies to every phase.

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-trigger-dispatch`);
gates re-run in full at Phase 4; PR body carries the demo transcript + near-duplicate audit
statement + this PLAN in a `<details>` block at close-out.
