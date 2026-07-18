# Return accounting

Normative convention for capturing RETURN — not activity — from autonomous-class work: a
lightweight, tracker-resident record at the task boundary, answering two human-attested
questions, joinable to machine cost telemetry by the work-item join attribute the telemetry
contract owns. No standalone estimation or reporting capability; no new cost.

## Three-layer data model

1. **Machine / deterministic** — automation cost (tokens, currency, wall time) from existing
   session telemetry, plus lifecycle metadata definitively calculable from tracker timestamps
   and exports. Never re-instrumented; this layer is the telemetry contract's concern.
2. **Human-attested** — (a) the counterfactual: would the org have spent engineering effort on
   this anyway (`yes` | `no` | `partial`); (b) the manual-effort band (below).
3. **Agent / LLM** — prompts for layer 2 at the task boundary and analyzes/aggregates over
   layers 1+2. It NEVER estimates, imputes, or backfills the two human-attested fields.
   Revisit trigger: models proven capable at effort estimation — the constraint is
   conditional, not permanent.

## Record schema (v1)

| Field | Value |
|---|---|
| `schema_version` | string, from `"1"` |
| `work_item_url` | the join key; value contract defined by the telemetry contract's `autonomy.work_item.url` |
| `attested` | boolean |
| `counterfactual` | `yes` \| `no` \| `partial` |
| `effort_band` | one of six contiguous ordinal tokens: `<1h`, `1-4h`, `4h-1d`, `1d-1w`, `1w-1mo`, `>1mo` — serialized as those exact strings; ordinal order is defined by this contract, never lexical |
| `attested_at` | ISO 8601 UTC timestamp |
| `attested_by` | the attesting human's platform identity, captured from the attestation action |
| `attestor_role` | `requester` \| `reviewer` \| `maintainer` \| `other` (descriptive — never the trust anchor) |

Presence rules: an unattested record carries `attested: false` with `counterfactual`,
`effort_band`, `attested_at`, `attested_by`, and `attestor_role` ABSENT — never null-imputed.
An attested record carries all fields.

Composition rule: `effort_band` answers the manual-cost question for the WHOLE delivered item
regardless of the `counterfactual` value; `partial` qualifies the counterfactual only.
Aggregation derives avoided cost from the pair; the attestor never prorates.

The band set and counterfactual enum are contract-stable: any change is a reviewed contract
migration, never per-org variation (org-custom bands break cross-org aggregation).

## Record lifecycle — attestation is asynchronous

Autonomous-class work has no human at the close boundary by construction, so:

1. At the task boundary (work-item close / change merge), the machine posts the UNATTESTED
   record plus an attestation request routed to the accountable human. The close flow never
   blocks on a human.
2. Attestation later upserts the SAME record to `attested: true`, adding the attested fields.
3. A never-attested record stays visible as unattested — missing data is visible, never
   imputed.

Attestation routing for requester-less classes (standing routines, scheduled sweeps): the
binding declares a standing attestation owner per class, or marks the class
attestation-exempt with its cost reported separately — never a perpetually-unattested
default.

Capture scope: autonomous-class work only, per the guardrail contract's class vocabulary;
interactive work is exempt (prompting friction kills compliance; divergence lives where no
human is in the loop). Expansion trigger: aggregate spend concentrating in interactive work.

## The prompt — two fields, never more

Canonical basis, near-verbatim:

1. "Would you have spent engineering effort on this anyway?" — `yes` / `no` / `partial`
2. "What would it have cost in manual eng-hours?" — one effort band

Non-blocking, with an explicit skip affordance; a skip leaves the record unattested.

## Tracker binding seam

The record surface resolves per tracker class through the binding:

- **Native fields** where the tracker class supports them (org-managed item fields,
  project-scheme fields, work-item fields) — the stronger surface where entitled: platform
  ACLs govern writes.
- **Structured comment** as the universal floor (every tracker class has comments): a hidden
  marker `<!-- autonomy:return-accounting:v1 -->` plus one fenced JSON block holding the
  record. Upsert is marker-keyed: find the marker comment, edit it in place, else create it.

Record integrity: a conforming record is authored by the deployment's
bound automation identity; consumers MUST ignore marker-matching records from any other
author. Attestor
identity derives from the PLATFORM actor of the attestation action — on the comment floor the
upsert itself is bot-authored, so `attested_by` MUST be copied from, and the record MUST
cite, the attestation source event (the human's reply or reaction whose platform actor
answered).

Duplicate tolerance: the standalone capture path's find-then-create has an inherent
create-create race. Dedupe on read is ATTESTATION-PRESERVING: an attested bot-authored record
outranks any unattested one; only among equally-attested records does the latest win. The
write rule has the same property: the close trigger creates the unattested record only when
no marker-matching bot-authored record exists — a re-fired or retried close NEVER overwrites
or downgrades an existing record's attestation fields.

## The join — query-side only

The return record and the cost telemetry both carry the work-item join value; the join
happens at the sink at query time against cost telemetry (resource-scoped on agent-session
signals per the telemetry contract). Cost values are never duplicated into the tracker
record; aggregation and reporting transport are the telemetry contract's sink concern.

Aggregation guidance: report the ATTESTATION RATE as a first-class health signal — a
collapsed rate invalidates the dataset as promotion evidence — and separate
requester-attested from independently-attested rows (a self-attested counterfactual is a
conflict of interest).

## Telemetry is not return

Usage measures activity. Only the two human-attested fields answer the return question; no
capability may present telemetry alone as return, and no capability may estimate the
human-attested fields.
