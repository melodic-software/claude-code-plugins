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
never overwrites or downgrades an existing record):

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

On a reply/reaction from the accountable human, the bound automation identity edits the SAME
marker comment, adding the attested fields — `attested: true`, `counterfactual`,
`effort_band`, `attested_at`, `attested_by` (copied from the reply's platform actor), and
`attestor_role` — plus a citation of the attestation source event (the reply's URL) so the
identity is auditable. Consumers ignore marker records from any author other than the bound
automation identity, and dedupe attestation-preservingly (attested outranks unattested;
latest wins only among equals).

## Close-trigger shape

Wire the capture at the task boundary the org actually has: a close-triggered workflow
(`<work-item closed>` / `<change merged>` event) invoking the record post + attestation
request. Route the comment write through the work-items comment seam where present;
otherwise the standalone snippet posts directly (create-only-when-absent per the contract's
race rule).
