# Trigger-adapter templates

Adapter shapes the trigger/dispatch slice wires, one per surface class. `<...>` placeholders
resolve from the binding at wire time; no org, fleet, or vendor value is baked in — vendor
event names appear only as marked examples. Every shape carries the contract's six adapter
obligations inline: normalize+enqueue only, idempotent dedup, provenance + raw link,
traceparent injection, admission enforcement, acknowledgment. Every shape STAMPS
`signal.work_class` from the security-surface classification rules where they resolve, and
leaves it absent (unclassified → human-gated) where they do not.

## Signal envelope (all classes)

The enqueue step writes the contract's marker record into the created item body — the
marker line plus one fenced JSON block:

```markdown
<!-- autonomy:signal:v1 -->
```

```json
{
  "schema_version": "1.0",
  "signal.class": "<surface-class token>",
  "signal.transport": "<push|push-lifecycle|poll>",
  "signal.provenance": "<human|agent|system>",
  "signal.identity": "<dedup identity — derivation below>",
  "signal.raw_link": "<durable absolute reference to the source event>",
  "signal.traceparent": "<W3C traceparent from the trigger hop>",
  "signal.work_class": "<C1-C5 where the classification rules resolve; omit otherwise>",
  "signal.parent_item": "<agent-internal only: canonical URL of the emitting session's admitted source item>",
  "signal.source_surface": "<temporal only: surface id recorded in the binding's surfaces map>"
}
```

Dedup identity derivation (obligation 2): use the surface-native unique event id where the
surface issues one (delivery id, event id). FALLBACK — never a bare content hash — compose
`<surface-class>:<origin-locator>:<delivery-id-or-event-timestamp>:<content-hash>`. The
enqueue is an atomic identity-keyed create/upsert where the tracker offers one; otherwise
search-before-create backed by create-then-reconcile (re-search after create; oldest wins,
close the newer as an audited duplicate).

## tracker-vcs-event — event kick → enqueue

A platform event workflow (marked example, GitHub Actions class: `on: issues` types
`labeled`/`assigned`, `on: issue_comment` type `created` for @-mention forms,
`on: pull_request` — the workflow file must exist on the default branch to fire):

1. Filter to the signal condition (`<trigger-label>` applied, assignment to
   `<automation-identity>`, @-mention token).
2. Derive `signal.identity` from the platform delivery/event id.
3. Stamp `signal.work_class` via the security-bound label→class rules; unresolvable → omit.
4. Enqueue via the bound work-item capability (create the queue item carrying the envelope);
   `signal.raw_link` = the triggering event's permalink (query/fragment preserved);
   `signal.provenance` = `human` for a human actor, `agent`/`system` per the acting
   identity; inject `signal.traceparent`.
5. Admission enforcement: no admission binding → the item is created human-gated (the
   fail-closed floor); never dropped.
6. Acknowledge: comment the item reference back on the source event per
   [`ack-reply.md`](ack-reply.md).

## temporal — scheduled drain + poll-detector

Two shapes on the same scheduled surface (marked example: `schedule` cron — shortest
interval 5 minutes, delays under load, 60-day public-repo auto-disable — plus
`workflow_dispatch` for manual kicks):

- **Drain** (dispatch, not an adapter): invoke the work-item queue capability's autonomous
  drain mode via the invocation-adapter seam — the seam lease claims race-safely; the drain
  never re-scans source surfaces, and never claims an item whose `signal.identity` matches
  another currently-open item (live-duplicate guard).
- **Poll-detector** (adapter): observe the push-less or `push-lifecycle`-backstopped
  surface, and for each detected condition enqueue the envelope with
  `signal.transport: "poll"`, `signal.source_surface` = this surface's id in the binding's
  `surfaces` map, `signal.raw_link` = a durable reference to the observed state (https
  permalink; a local-scheduler surface may use an absolute `file:` or artifact-store URI).
  State-based detections with no instance identity bound dedup retention to open items —
  re-detection after closure is a new signal.

## agent-internal — session files follow-up via the queue seam

No standing wiring: an executing session files follow-up work through the queue seam
directly, carrying the envelope with `signal.provenance: "agent"` and
`signal.parent_item` = the canonical URL of the item the session was dispatched on
(REQUIRED — the admission seam verifies the session-to-parent association against the
queue's own lease record; an unverifiable association is NO provenance → unclassified →
human-gated). `signal.raw_link` = a durable reference to the emitting context (the parent
item or its run permalink). Dedup identity composes the parent item + the follow-up's
content hash + the filing timestamp.

## channel-feed — webhook receiver → enqueue

A chat-platform bot events subscription or a plain inbound webhook receiver (DIY floor;
vendor-hosted channel agents are advisory, plan-gated):

1. Validate the subscription handshake where the platform requires one; `push-lifecycle`
   transports record expiry and are backed by a temporal poll-detector for the same
   surface, or lapse fail-closes to a human-gated alert item.
2. Derive `signal.identity` from the platform's event/delivery id.
3. Enqueue the envelope; `signal.work_class` stays absent (channel-feed is UNCLASSIFIED →
   human-gated) unless security-bound rules resolve it; `signal.raw_link` = the message/
   event permalink.
4. Acknowledge in-thread per [`ack-reply.md`](ack-reply.md).
