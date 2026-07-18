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
> Reply to this comment with your answers (e.g. `partial, 1-4h`) — or skip; a skip leaves the
> record unattested.

## Marker-keyed record comment (universal floor)

Posted at close ONLY when no marker-matching bot-authored record exists (a re-fired close
never overwrites or downgrades an existing record). These two blocks together form the
complete comment body — both appear in the same tracker comment:

```markdown
<!-- autonomy:return-accounting:v1 -->
```

```json
{
  "schema_version": "1",
  "work_item_url": "<canonical-item-url>",
  "attested": false
}
```

## Attestation upsert

Attestation requires a REPLY whose platform actor IS the item's accountable human — the
requester the request was addressed to, or the binding's standing attestation owner for
requester-less classes; a reply from any other participant is never upserted (the actor
check is the trust anchor here; `attestor_role` stays descriptive). The reply must carry
BOTH values (`counterfactual` and `effort_band`); a bare reaction cannot carry them and never triggers
the upsert — the automation leaves the record unattested (optionally re-requesting with the
expected reply shape). On a parseable reply, the bound automation identity edits the SAME
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
request. Route the comment write through the work-items comment seam where present;
otherwise the standalone snippet posts directly (create-only-when-absent per the contract's
race rule).

## Attestation-reply trigger shape

Wire a companion reply-triggered handler at the surface the org's tracker actually offers (a
comment-created event, or the native-field equivalent where fields support change-triggered
automation): on each new reply to the marker-tagged item, resolve the actor against the
accountable-human routing and, on a parseable reply carrying both values, perform the SAME
upsert above — not a second contract, the one attestation upsert wired from its own trigger.
Where no reply-triggered surface is machine-editable, this is advisory: surface that
attestation would require a manual upsert rather than silently wiring only the close half.
