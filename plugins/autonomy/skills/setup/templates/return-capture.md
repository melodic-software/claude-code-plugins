# Return-capture templates

Close-boundary capture shapes the return-accounting slice wires. `<...>` placeholders resolve
from the binding at wire time; no org, fleet, or vendor value is baked in.

## The prompt (canonical, exactly two fields)

> This item was completed by autonomous work. Two questions:
>
> 1. **Would you have spent engineering effort on this anyway?** — `yes` / `no` / `partial`
> 2. **What would it have cost in manual eng-hours?** — `<1h` / `1-4h` / `4h-1d` / `1d-1w` /
>    `1w-1mo` / `>1mo`
>
> Reply to this comment with your answers (e.g. `partial, 1-4h`) — on trackers without
> threaded replies, start a new comment on this item with `attest:` (e.g. `attest: partial,
> 1-4h`) — or skip; a skip leaves the record unattested.

## Marker-keyed record comment (universal floor)

Posted at close ONLY when no marker-matching bot-authored record exists (a re-fired close
never overwrites or downgrades an existing record). The complete comment body is THREE
parts in the one tracker comment: the marker block, the fenced JSON record, and the
canonical two-question prompt above, addressed (platform @-mention) to the accountable
human — the requester resolved via the binding's requester-identity source, or the standing
attestation owner for requester-less classes. Without the addressed prompt the close flow
would record without ever requesting attestation. The two machine blocks:

```markdown
<!-- autonomy:return-accounting:v1 -->
```

```json
{
  "schema_version": "1",
  "work_item_url": "<canonical-item-url>",
  "attested": false,
  "attestation_request": "<request-event-url>",
  "attestation_owner": { "identity": "<platform-identity>", "role": "<derived-role>" }
}
```

`attestation_request` anchors the contract's reply-correlation rule. On the comment floor
the request and record share the marker comment, so the request event IS the marker comment
itself: correlation keys on the marker comment's identity (a reply to it, or the flat-tracker
`attest:` form), and the stored URL is its serialized citation. The close trigger backfills
the URL with a self-edit immediately after posting; the backfill is IDEMPOTENT-RECOVERABLE —
any later automation pass (a re-fired close, the reply handler) that finds the marker record
with `attestation_request` missing fills it from the marker comment's own identity without
touching any other field (the create-only rule protects the record's attestation fields, not
this machine backfill), so a failed self-edit or a fast reply never orphans attestation. On
native fields it is the URL of the posted request comment, with the SAME recovery property:
if the request posted but persisting the field failed, any later automation pass locates its
own request comment on the item (bot-authored, carrying the canonical prompt) and fills the
missing field — or re-posts the request when none exists — without touching any attestation
field.

## Attestation upsert

Attestation requires a REPLY whose platform actor IS the record's `attestation_owner`
snapshot — resolved ONCE at close (through the binding's requester-identity source for the
tracker class, or the standing attestation owner for requester-less classes) and persisted
on the record; the handler validates against the snapshot, never a re-resolution, so a
post-close edit of the underlying source cannot move ownership. A reply from any other
participant is never upserted (the actor
check is the trust anchor here; `attestor_role` stays descriptive and is DERIVED at close
into the `attestation_owner` snapshot, never free-chosen: `requester` when close-time
resolution went through the binding's requester-identity source, else the matched routing
entry's declared role, defaulting to `other` — the handler writes the snapshot's role). The reply must carry
BOTH values (`counterfactual` and `effort_band`); a bare reaction cannot carry them and never triggers
the upsert — the automation leaves the record unattested (optionally re-requesting with the
expected reply shape). Actor + parseable payload alone are not enough: per the contract's
reply-correlation rule the event must RESPOND to the recorded `attestation_request` — a
platform reply/thread relationship to that event, or on flat-comment trackers an
`attest:`-prefixed comment on the request's item; an incidental parseable comment elsewhere
on the item never attests. On an admissible reply, the bound automation identity edits the SAME
marker comment, adding the attested fields — `attested: true`, `counterfactual`,
`effort_band`, `attested_at`, `attested_by` (copied from the reply's platform actor),
`attestor_role`, and `attestation_source` (the reply event's canonical URL as the platform
serves it — a well-formed absolute https URL; query and fragment are PRESERVED, since many
platforms identify the comment event in them; the telemetry contract's strip rule applies
only to the work-item join key) — so the identity is auditable. `attestation_source` is a
schema key, present on every attested record on both surfaces (on native fields it maps to a
field of the same name). A reply missing either value is answered with the expected shape
and does not upsert.

Attested record shape (the same fenced JSON record, upserted):

```json
{
  "schema_version": "1",
  "work_item_url": "<canonical-item-url>",
  "attested": true,
  "attestation_request": "<request-event-url>",
  "attestation_owner": { "identity": "<platform-identity>", "role": "<derived-role>" },
  "counterfactual": "partial",
  "effort_band": "1-4h",
  "attested_at": "<iso-8601>",
  "attested_by": "<platform-actor>",
  "attestor_role": "<role>",
  "attestation_source": "<reply-event-url>"
}
``` Consumers ignore marker records from any author other than the bound
automation identity, and dedupe attestation-preservingly (attested outranks unattested;
latest wins only among equals).

## Close-trigger shape

Wire the capture at the task boundary the org actually has: a close-triggered workflow
(`<work-item closed>` / `<change merged>` event) invoking the record post + attestation
request. A `<change merged>` event identifies a change, not the work item the record lives
on: the handler resolves the merged change's linked work items through the platform's
closing-link references and FANS OUT per item — each linked item independently runs the
full eligibility gate and, when admitted, receives its own record (its own canonical item
URL as the join key, its own owner snapshot and record-surface target). One merge closing
several items yields one record per item; a merge with no resolvable linked work item
captures NOTHING — a record attached to the change URL would never join the per-work-item
telemetry. Where a work-item-tracker binding is present, the comment write uses the bound
adapter's documented comment operations (comments are provider-specific mechanics there —
the tracker seam exposes no comment verb); otherwise the standalone snippet posts directly
(create-only-when-absent per the contract's race rule).

## Attestation-reply trigger shape

Wire a companion reply-triggered handler on the tracker's comment-created event surface (a
native-field-change trigger is not a substitute — no v1 field-edit protocol carries the two
attested values, so a tracker without a comment-created surface routes to the advisory path
even when field-change automation exists): on each new reply, resolve the actor against the accountable-human routing,
require the reply-correlation rule (a response to the recorded `attestation_request`, or the
flat-tracker `attest:` token) and,
on a parseable reply carrying both values, upsert the SAME attested record — not a second
contract, the one attestation upsert wired from its own trigger. On the comment floor this
means finding the marker-tagged comment and editing it in place (a missing marker comment
means no close-time record — the reply admits nothing, per the contract's
attestation-never-creates rule); on native fields there is no marker to find, but the same
rule binds: the handler first verifies the close-time unattested record is present on the
item's fields and treats its absence as inadmissible — and on an audit-trail-selected
surface additionally confirms the trail attributes the record's CREATION and EVERY
SUBSEQUENT REVISION of the record fields to the bound automation identity (presence alone
is forgeable where fields are not ACL-restricted, and a later non-automation edit — notably
an altered `attestation_owner` — makes the record non-conforming and rejected before the
owner snapshot is trusted or any attested field written) — only then writing the attested
fields directly on that item (the fields already belong 1:1 to the closing item). Where no
reply-triggered surface is machine-editable, this is advisory: surface that
attestation would require a manual upsert rather than silently wiring only the close half.
