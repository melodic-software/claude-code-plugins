# Trigger dispatch

Normative contract for signal adapters and autonomous dispatch: adapters normalize signals
from four surface classes into the governed work-item queue; one dispatch entrypoint drains
it; the executor is swappable behind the invocation-adapter seam. The contract fixes
vocabulary, obligations, and invariants; every concrete instance (which surfaces exist,
which tracker holds the queue, where the executor runs) is an org-binding outcome.

## Signal-surface classes

Four classes, ALL contract-active. Per-org availability is a binding outcome — a surface the
org lacks, or an entitlement gap on a surface it has, routes to the advisory path; it is
never a contract deferral.

| Class token | Surface |
|---|---|
| `tracker-vcs-event` | Tracker/VCS-host events: label applied, assignment, @-mention, PR event |
| `temporal` | Schedules and poll-fallback detectors for push-less surfaces |
| `agent-internal` | A session emits follow-up work while executing |
| `channel-feed` | Chat mention and continuous channel/data-feed monitoring |

Carried research gaps, stated in surface-class vocabulary (vendor specifics live in the
setup skill, never here): whether a channel-monitor may ambiently INITIATE work versus only
notify is UNVERIFIED; the channel-agent surfaces this class relies on are alpha/beta moving
targets; one major chat platform has no first-party trigger (UNVERIFIED-absence — re-verify
at wire time).

## Recorded signal attributes

Two attributes are recorded on every queued signal:

- **Initiator provenance** — `human` | `agent` | `system`. Audit data and guardrail-matrix
  input; recorded, never trusted as an isolation axis (provenance is claimable; isolation
  decisions key on the work class and surface verdicts, not on who claims to have asked).
- **Transport** — `push` | `push-lifecycle` | `poll`. Push preferred where the surface
  offers it; poll is the universal fallback via the `temporal` class. `push-lifecycle`
  carries subscription obligations: expiry tracking, renewal, and the platform's validation
  handshake. Expiry semantics are normative: every `push-lifecycle` wiring is backed by a
  `temporal` poll-detector backstop for the same surface, or the subscription-health lapse
  fail-closes — it files a human-gated alert item — so a lapsed subscription can never
  silently drop signals.

## Adapter obligations

Six class-generic obligations bind every adapter:

1. **Normalize and enqueue only.** An adapter never executes work and never bypasses the
   queue — the adapter-side face of the [one-entrypoint invariant](#dispatch), which that
   section states canonically.
2. **Idempotent dedup**, keyed on `signal.identity`. The identity is the surface-native
   unique event id where the surface issues one. The FALLBACK identity is never a bare
   content hash: it composes source scope (surface class + origin locator) + an
   event-instance discriminator (delivery id or event timestamp) + the content hash, so two
   legitimate repeated signals with identical payloads stay distinct instances. State-based
   poll detectors that re-observe a continuing condition have no instance identity; their
   dedup retention is BOUNDED to items still open — the same finding may re-enqueue once its
   prior item closes (a re-detected regression is a new signal). Enforcement is not a bare
   read-then-write: concurrent at-least-once deliveries can both pass a search before either
   item exists, so the adapter uses an atomic identity-keyed create/upsert or queue-side
   uniqueness guarantee where the tracker offers one; otherwise search-before-create is
   backed by create-then-reconcile — after creating, re-search by `signal.identity` and, on
   finding an older item with the same identity, close the newer one as an audited duplicate
   (oldest wins, deterministically). A drain-side guard scoped to LIVE duplicates completes
   the defense: the drain never claims an item whose `signal.identity` matches another
   currently-open item, while completed items are excluded from the guard so re-detections
   execute.
3. **Provenance capture and a durable raw-signal link** (`signal.raw_link`) on the item.
4. **Trace-context propagation.** The adapter injects `signal.traceparent` so the telemetry
   contract's causal tree spans trigger → CI → agent session.
5. **Admission enforcement at the seam.** Admission-policy CONTENT is owned by the guardrail
   matrix and bound on the org's security governance surface; the adapter ENFORCES it,
   never defines it. An unadmitted signal becomes a human-gated item or an audited
   rejection — never a silent drop. An ABSENT admission binding fail-closes: everything
   enqueues human-gated.
6. **Closed-loop acknowledgment.** Bidirectional surfaces echo the queued item reference
   back to the source (tracker comment, chat thread reply); reply-less surfaces satisfy the
   obligation through `signal.raw_link` alone.

## Work-class classification

Admission and the whole guardrail matrix key on the risk class (`C1`–`C5`), so a queued item
needs one. The adapter STAMPS `signal.work_class` from the classification rules on the org's
SECURITY governance surface — the adapter stamps, never defines, and no repo-local
(agent-writable) surface may supply the class used for admission:

- `tracker-vcs-event` resolves through the security-bound label→class rules.
- `temporal` signals split by producer. A ROUTINE-fired temporal signal — one carrying the
  validated `signal.routine` identity of an enabled routine, whose `routines.enabled` entry
  references the emitting surface (the surface record itself may live under `triggers` and be
  REUSED by the routine) — carries the class its bound routine definition derives
  ([routine contract](routines.md)), including woken routine runs, event or continuous feed,
  which are `temporal` regardless of wake source. A temporal poll-fallback DETECTOR emission —
  one claiming no routine identity — derives no class: it stays unclassified, and a stamped
  `signal.work_class` (or a producer identity) on it is rejected fail-closed, as is a claimed
  identity that no enabled routine records or whose recorded surface disagrees.
- `agent-internal` items must PROVE protected provenance: the envelope serializes the
  emitting session's own admitted source item as `signal.parent_item`, and the admission
  seam verifies the session-to-parent association against protected dispatch data — the
  queue's own lease record of which item the emitting session was dispatched on. An
  agent-supplied URL alone proves nothing (any session could cite an unrelated low-class
  item to launder higher-risk follow-up work); an association the seam cannot verify is NO
  provenance. Admission then resolves the verified parent's class from its own protected
  classification rather than trusting the stamped value: the effective class is the HIGHER
  of the inherited class and the class the security-surface rules derive for the target.
- `channel-feed`, and any signal the rules cannot resolve, stays UNCLASSIFIED. `signal.routine`
  identifies a routine-fired temporal run only — the envelope check rejects the stamp on a
  detector-fired temporal signal and on every non-temporal class, so a `channel-feed` signal
  never carries a routine run.

Unclassified → fail-closed human-gated, always.

**Authenticated run context.** Envelope fields are agent-claimable, so a temporal adapter
resolves `signal.source_surface`, `signal.raw_link`, and `signal.producer_identity` from the
platform's authenticated run context — the run identity, and the workflow-file or
scheduler-unit reference, that the scheduling platform itself injects — never from job arguments
or agent-writable configuration. The security binding's ratified entry pins each routine
identity to a run-permalink namespace (`run_link_prefix`) AND to the platform-attested
`producer_identity`. The namespace may be repo-scoped and SHARED across a repo's schedules, so
it is no longer disjoint per entry: the prefix pins the platform-and-repo namespace, and the
`producer_identity` pins WHICH schedule within it (producer identities are unique across
entries). Attestation is therefore both — a raw link inside the ratified prefix AND a
`producer_identity` equal to the ratified value; a raw link outside the namespace, or a producer
identity that does not match, fails the identity-to-surface association check
([routine contract](routines.md)) and the signal stays unclassified — fail-closed human-gated,
like any claim the [admission seam](guardrails/admission-policy.md) cannot verify.

## Signal envelope

Serialization is a JSON-fenced marker record on the queued item (the return-accounting
convention's marker-record precedent): the marker `<!-- autonomy:signal:v1 -->` plus one
fenced JSON block holding the record, written by the adapter at enqueue. `schema_version`
starts at `"1.0"` with additive evolution under the same reviewed-migration governance as
every contract schema. Keys:

| Key | Value |
|---|---|
| `signal.class` | surface-class token |
| `signal.transport` | `push` \| `push-lifecycle` \| `poll` |
| `signal.provenance` | `human` \| `agent` \| `system` |
| `signal.identity` | dedup identity per obligation 2 |
| `signal.raw_link` | durable absolute reference to the source event; form branched by origin — web-origin signals carry an absolute https URL with query and fragment PRESERVED (the telemetry contract's strip rule applies only to the work-item join key); a temporal signal from a local-scheduler surface may carry a durable local/artifact URI (absolute `file:` URI or org artifact-store locator); relative or ephemeral references conform on no branch |
| `signal.traceparent` | W3C trace context from the trigger hop |
| `signal.work_class` | optional; the stamped risk class per the classification rules — absent = unclassified = human-gated |
| `signal.parent_item` | REQUIRED when `signal.class` is `agent-internal`: canonical URL of the emitting session's admitted source item, verified against the queue's lease record |
| `signal.source_surface` | REQUIRED when `signal.class` is `temporal`: the originating scheduling surface's id as recorded in the org's trigger/routine binding — the discriminator raw-link form validation branches on |
| `signal.routine` | REQUIRED for a ROUTINE-fired `temporal` signal — one whose identity a `routines.enabled` entry records against the emitting surface (the surface record itself may live under `triggers` and be reused); FORBIDDEN on every non-temporal class, and absent on a detector-fired `temporal` signal. The routine identity the emitting schedule claims ([routine contract](routines.md)); a CLAIM validated against the enablement record and the security binding's protected identity-to-surface association (one identity per surface) before any `signal.work_class` stamp — an unvalidated or mismatched claim stays unclassified, fail-closed human-gated |
| `signal.producer_identity` | REQUIRED for a ROUTINE-fired `temporal` signal; `temporal`-only. The platform-attested workflow-file or scheduler-unit reference resolved from the authenticated run context; checked for equality with the ratified `producer_identity` and unique across classification entries — the discriminator that pins WHICH schedule fired within a possibly-shared run-link namespace |

## Dispatch

Push kick where the platform offers it (an event-fired job on enqueue) plus a standing
scheduled drain as the universal fallback and catch-up net for ENQUEUED items. The drain's
default cadence is hourly (org-bindable); the drain never re-scans a source surface —
missed enqueues are the poll-detector backstop's job.

**One-entrypoint invariant.** Every kick funnels into the work-item queue capability's
existing autonomous drain mode via the invocation-adapter seam. The seam's race-safe lease
makes concurrent kicks harmless. **No second path from signal to execution, no second claim
path, and no second dispatch mechanism exists anywhere.** This paragraph is the invariant's
canonical statement; every sibling contract cites it rather than restating it, so its scope
cannot drift by re-wording.

**Scope.** The invariant governs the governed-queue path: any mechanism that claims a queued
work item, or that dispatches autonomous execution against one. Three consequences follow.

- A surface that reaches a repository WITHOUT claiming a queued item is outside the
  invariant, not an exemption from it — an interactive session a human drives, or a lane
  that advances existing changes without claiming work items, takes no claim and so has no
  second claim path to be. It remains bound by every other guardrail its work class carries.
- A surface that DOES claim queued work is inside the invariant no matter how it is invoked
  — interactively, on a schedule, or from an event — and claims through this entrypoint or
  not at all.
- The boundary is a property of the SURFACE's behavior, never of its category: a lane
  crosses in the moment it starts claiming items, and neither its name, its plugin, nor its
  prior classification grants it standing outside.

The distinction is not load-bearing while only one claiming surface exists. It becomes
load-bearing the moment a second one does — which is why it is written before the runner is
built rather than after two surfaces disagree.

**Execution-surface attestation.** Every kick/drain wiring records its named execution
surface, but the recorded id is repo-local convenience only: the admission/executor seam
derives the ACTUAL execution-surface identity from trusted dispatch/runner context —
platform-attested runtime metadata matched against the per-surface identifying markers the
security binding's isolation entries declare — and verifies it against the recorded id,
consulting the ACTUAL surface's isolation verdict. A mismatch, an unattestable actual
surface, or a surface without the required isolation binding each fail-close to
human-gated; rewriting the recorded id cannot launder execution onto an unbound runner.

Concurrency and per-run item caps are guardrail-policy knobs: this contract names them
descriptively; their serialized tokens (`autonomous_concurrency`, `items_per_run`) are
owned by the admission policy on the security surface.

## Executor surface classes

Two classes, imported unchanged from the runner charter: **self-operated** CLI/SDK
executors — including SDK-embedded pull/drain daemons — and **vendor-hosted** executors,
whose merge policy caps at human-gated. The executor-class determination that gates merge
policy is SECURITY-surface data (the security binding's `executor_class`), never a
repo-local value. Other executor hosting configuration is deployment-owned per the hosting
stance: this contract fixes only the isolation floor (L2+ for unattended execution),
credential scoping, and the queue contract.

## Constraints

- The [one-entrypoint invariant](#dispatch) and its scope boundary bind every surface this
  contract governs.
- The contract never invents an event bus and never raises domain events; the adopting
  org's own systems own event definition and raising.
- No new cost by default: paid surfaces are advisory with cost surfaced, explicit opt-in.
- Vendor and fleet names never appear in this contract's normative text; mechanisms are
  named as classes with vendor specifics in binding docs and the setup skill.
