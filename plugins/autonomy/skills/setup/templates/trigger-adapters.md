# Trigger-adapter templates

Adapter shapes the trigger/dispatch slice wires, one per surface class. `<...>` placeholders
resolve from the binding at wire time; no org, fleet, or vendor value is baked in, and vendor
event names appear only as marked examples. Every shape carries the contract's six adapter
obligations inline: normalize+enqueue only, idempotent dedup, provenance + raw link,
traceparent injection, admission enforcement, acknowledgment. Every shape STAMPS
`signal.work_class` from the security-surface classification rules where they resolve, and
leaves it absent (unclassified → human-gated) where they do not.

## Signal envelope (all classes)

The enqueue step writes the contract's marker record into the created item body, the
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
surface issues one (delivery id, event id). FALLBACK, never a bare content hash: compose
`<surface-class>:<origin-locator>:<delivery-id-or-event-timestamp>:<content-hash>`. The
enqueue is an atomic identity-keyed create/upsert where the tracker offers one; otherwise
search-before-create backed by create-then-reconcile (re-search after create; oldest wins,
close the newer as an audited duplicate).

## tracker-vcs-event: event kick → enqueue

A platform event workflow (marked example, GitHub Actions class: `on: issues` types
`labeled`/`assigned`, `on: issue_comment` type `created` for @-mention forms,
`on: pull_request`, where the workflow file must exist on the default branch to fire):

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
7. Kick the drain: after enqueue + ack, invoke the SAME queue-drain entrypoint (the
   work-item queue capability's autonomous drain mode via the invocation-adapter seam) so
   push-originated work gets an event-fired dispatch attempt instead of waiting for the
   scheduled catch-up. There is one entrypoint, and concurrent kicks are harmless via the seam lease;
   admission still governs what the drain may execute (absent binding → the item stays
   human-gated).

### GitHub adapter: the autonomous-eligible label kick

A kick with no enqueue, for the case where the item is already the queue item: someone applies
`<autonomous-eligible-label>` (the work-items autonomous-eligible label, `agent-ready` unless the
consumer renamed it) to an open issue. Marked example, GitHub Actions class: `on: issues` type
`labeled`, in a workflow on the default branch. This repository ships no such workflow.

Only a trusted human's label kicks. Everything else does nothing and exits 0:

1. **Match the label in the `if:` expression.** The job runs only when
   `github.event.label.name` equals `<autonomous-eligible-label>` as an exact string. The label
   name, issue title, body and comments are untrusted data: none of them appears in a `run:`
   line, a shell argument, a request body or a log line the job writes.
2. **Check the actor, never the text.** The actor is the label event's `sender`, not the issue
   author. The kick proceeds only when `sender.type` is `User` and
   `GET /repos/{owner}/{repo}/collaborators/{sender.login}/permission` returns `permission`
   `admin` or `write`. A bot or App label, a `read` or `none` permission, a login that does not
   match `^[A-Za-z0-9-]+$`, an API error or an unreadable response each mean untrusted. The login
   reaches the step through `env:`, never through `${{ }}` inside `run:`. Issue text never
   decides trust. An App acting through a write user's user access token labels as that
   user and passes this check, so "an App label does nothing" holds for installation tokens
   only.
3. **Resolve the drain's `execution_target`.** Read `skill.work-items.work-loop` from
   `docs/conventions/execution-target.yaml` at the commit the event runs on (the default branch),
   resolved per that convention's Resolution order (`skill` key, then `default`, then
   `local-worktree`). A missing or rejected file resolves `local-worktree`.
4. **Kick or leave it to the schedule.**
   - `cloud-routine`, and the execution-target convention admits `work-items:work-loop` to cloud
     hosts: POST the routine's `/fire` URL (`<routine-fire-url>`) with the bearer token from the
     CI secret store (`<routine-fire-token-secret>`) and no `text` field. The routine's saved
     prompt runs the drain; nothing from the issue is forwarded. Today that convention refuses
     every cloud host for `work-items:work-loop`, because the work loop reads untrusted input
     when it triages raw intake, so this branch does not fire until the convention admits it.
   - `local-worktree` or `local-background`: the job does nothing. A hosted runner cannot reach
     the operator's machine, so a local target has no kick; the scheduled drain
     (`/harness-ops:lanes` `run-once`, on the schedule its `print-schedule` registers) claims the
     item on its next run.
   - `cloud-session`, `cloud-project`, or a `cloud-routine` the convention refuses: the job does
     nothing, and the scheduled drain also skips this lane, because the launcher refuses cloud
     hosts for this stage and `run-once` runs local hosts only. The item waits until the target
     is local.

The job enqueues nothing, writes no envelope, comments nothing, and never changes a label or a
work class, claims an item or merges. Admission still decides what the drain may execute; the kick
only shortens the wait. The job runs no model step.

Token and secrets: the job token needs `contents: read` (to read the policy file) and the
always-granted `metadata: read` (the permission endpoint); declare `permissions: contents: read`
and nothing else. The routine token is exposed only to the step that fires, after step 2 passes.
Labels need the triage role or higher, and triage maps to `read`, so a triage user's label does
not kick. The drain applies the same bar at admission: it reads who last applied the role and
`work-class:` labels and refuses the item unless each labeler holds `write` or higher (the
`work-items` plugin's `/work-items:work-loop`, "Admission gate").

Vendor facts this shape depends on:

- **Permission values.** Pointer:
  [Get repository permissions for a user](https://docs.github.com/en/rest/collaborators/collaborators#get-repository-permissions-for-a-user)
  (`admin`, `write`, `read`, `none`; maintain maps to `write`, triage to `read`) and the
  "Metadata" section of
  [Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).
  As of: 2026-10-04. Recheck trigger: the endpoint's role mapping or required permission changes.
- **Routine triggers.** Pointer: "Add an API trigger" and "Supported events" on
  [Routines](https://code.claude.com/docs/en/routines) (the `/fire` endpoint; `text` arrives as
  untrusted data; GitHub triggers cover pull request and release events, not issues). As of:
  2026-10-04. Recheck trigger: routines gain an issues trigger, or `/fire` leaves its beta header.
- **App actions on a user's behalf.** Pointer:
  [Authenticating with a GitHub App on behalf of a user](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-with-a-github-app-on-behalf-of-a-user)
  (requests made with a user access token are attributed to that user; an installation token
  attributes them to the App). As of: 2026-10-04. Recheck trigger: GitHub changes how user
  access token activity is attributed.

## temporal: scheduled drain + poll-detector

Two shapes on the same scheduled surface (marked example: `schedule` cron, with a shortest
interval of 5 minutes, delays under load, and 60-day public-repo auto-disable, plus
`workflow_dispatch` for manual kicks):

- **Drain** (dispatch, not an adapter): invoke the work-item queue capability's autonomous
  drain mode via the invocation-adapter seam, where the seam lease claims race-safely; the drain
  never re-scans source surfaces, and never claims an item whose `signal.identity` matches
  another currently-open item (live-duplicate guard).
- **Poll-detector** (adapter): observe the push-less or `push-lifecycle`-backstopped
  surface, and for each detected condition enqueue the envelope with
  `signal.transport: "poll"`, `signal.source_surface` = this surface's id in the binding's
  `surfaces` map, `signal.raw_link` = a durable reference to the observed state (https
  permalink; a local-scheduler surface may use an absolute `file:` or artifact-store URI). A
  detector-fired temporal signal carries NO `signal.routine` and never stamps
  `signal.work_class`. It stays unclassified (human-gated downstream), and a routine identity
  or a stamped class on it is rejected fail-closed. State-based detections with no instance
  identity bound dedup retention to open items, and re-detection after closure is a new signal.

The scheduled-ROUTINE shape is the temporal surface's other producer, wired per
[`routine-definitions.md`](routine-definitions.md): unlike the poll-detector it carries
`signal.routine`, and it resolves `signal.producer_identity`, along with `signal.source_surface`
and `signal.raw_link`, from the platform's authenticated run context, never from job arguments.

## agent-internal: session files follow-up via the queue seam

No standing wiring: an executing session files follow-up work through the queue seam
directly, carrying the envelope with `signal.provenance: "agent"` and
`signal.parent_item` = the canonical URL of the item the session was dispatched on
(REQUIRED: the admission seam verifies the session-to-parent association against the
queue's own lease record; an unverifiable association is NO provenance → unclassified →
human-gated). `signal.raw_link` = a durable reference to the emitting context (the parent
item or its run permalink). Dedup identity composes the parent item + the follow-up's
content hash + the filing timestamp.

## channel-feed: webhook receiver → enqueue

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

A continuous routine never enqueues its RUN here: the feed emission may wake the routine's
ratified temporal surface, and the run enters via the temporal adapter carrying `signal.routine`
and `signal.producer_identity`; `channel-feed` carries only the ordinary feed signal.
