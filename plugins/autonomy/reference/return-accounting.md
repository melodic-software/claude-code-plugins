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
| `attestation_source` | absolute https URL of the attestation source event (the human's reply) as the platform serves it — query and fragment PRESERVED (they often identify the comment event); the telemetry contract's strip rule applies only to the work-item join key. The auditable identity citation |
| `attestation_request` | machine-written at close: absolute https URL of the posted attestation-request event — the identity an admissible reply must respond to; present on the unattested record whenever a request was posted (absent only for attestation-exempt classes, which post no request) |
| `attestation_owner` | machine-written at close: the resolved accountable human's platform identity the request was addressed to (via the requester-identity source, or the standing-owner routing), with the role the resolution derived. The resolved owner MUST be a human platform account distinct from the bound automation identity — a resolution yielding a bot/app account (e.g. a bot-filed item under an item-author source) or the automation itself produces NO owned record: the item routes to its class's declared standing owner where one exists, else capture for that item stays advisory (a machine owner would let the automation attest its own record, bypassing the never-estimate rule). Reply actors are validated against THIS snapshot — never a re-resolution: a post-close change of the underlying source (field edit, reassignment) does not move ownership; deliberate rerouting is a new automation-posted request that updates the snapshot |

This record's `schema_version` uses major-only tokens (`"1"`, never `"1.0"`); the setup
skill's own binding `schema_version` uses semver strings — the two are separate version
spaces with independent parsers.

Presence rules: an unattested record carries `attested: false` with `counterfactual`,
`effort_band`, `attested_at`, `attested_by`, `attestor_role`, and `attestation_source`
ABSENT — never null-imputed. An attested record carries all fields. `attestation_request`
and `attestation_owner` are machine-layer (never human-attested) and ride both states.

Reply correlation: actor + parseable payload alone never attest — an accountable human can
type a parseable string in an unrelated discussion on the same item. An admissible
attestation reply must RESPOND to the recorded `attestation_request` event: the platform's
reply/thread relationship to that event where the tracker has one; on flat-comment trackers
(no threaded replies), an explicit response token opening the comment (`attest:` followed by
the two values) on the request's item. An incidental parseable comment matching neither is
ignored.

Composition rule: `effort_band` answers the manual-cost question for the WHOLE delivered item
regardless of the `counterfactual` value; `partial` qualifies the counterfactual only.
Aggregation derives avoided cost from the pair; the attestor never prorates.

The band set and counterfactual enum are contract-stable: any change is a reviewed contract
migration, never per-org variation (org-custom bands break cross-org aggregation).
Per-work-class precision graduation (finer bands for a class the guardrail matrix names) is
deferred with a trigger: aggregate data proving a class needs finer resolution. The record
never grows a class field for this: segmentation joins each record to its work item (the
telemetry contract's join attribute) and reads the item's admission-time class from the
governed queue's protected admission data — the surface that stamped and verified the class
at admission — falling back to re-derivation through the security-surface classification
rules (current-epoch class, a stated approximation) where queue history is not retained.

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
default. For ordinary (requester-carrying) items the requester IS the routing, but WHO the
requester is per tracker class (item author, a named custom field, another tracker-specific
identity) is not derivable from the tracker class token alone — the binding names the
requester-identity source the attestation request is addressed to and the attesting actor is
validated against; it is never guessed. A requester-less routing entry's per-surface key
must be RECOVERABLE FROM THE ITEM at close time: the filing surface stamps its identifier
on every item it files (an item-body marker, label, or field the binding records), and the
close/reply handlers resolve routing by reading that stamp — never by title matching or
other ad-hoc correlation. A surface that cannot stamp its identifier leaves its routing
entry unwired and reported.

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

Record integrity: a conforming record is authored by the deployment's bound automation
identity; consumers MUST ignore marker-matching records from any other author. The comment
floor carries authorship structurally (every comment is platform-attributed); native field
VALUES carry no author, so native fields are a conforming record surface ONLY where writes
to the record fields are restricted to the automation identity by platform ACL, or a
queryable field-audit trail attributes every write to its actor — absent both, a manually
edited field set would be indistinguishable from an authentic attestation, and the comment
floor applies. Attestor
identity derives from the PLATFORM actor of the attestation action — on the comment floor
the upsert itself is bot-authored, so `attested_by` MUST be copied from, and the record MUST
cite, the attestation source event (the human's reply whose platform actor answered — the
reply must carry both attested values; an actor-only signal such as a bare reaction cannot
attest). `attestor_role` is likewise DERIVED, never free-chosen: the derivation runs at
CLOSE TIME, when the accountable owner is resolved into the `attestation_owner` snapshot —
`requester` when resolution went through the binding's requester-identity source, else the
role the matched standing-owner routing entry declares (default `other`) — and the handler
writes the snapshot's role; the requester-attested versus independently-attested
aggregation split depends on this derivation.

Duplicate tolerance: the standalone capture path's find-then-create has an inherent
create-create race. Dedupe on read is ATTESTATION-PRESERVING: an attested bot-authored record
outranks any unattested one; only among equally-attested records does the latest win. The
write rule has the same property: the close trigger creates the unattested record only when
no marker-matching bot-authored record exists — a re-fired or retried close NEVER overwrites
or downgrades an existing record's attestation fields.

Attestation has the complementary property: it UPDATES an existing close-time unattested
record and never creates one. The eligibility gate lives at close time; attestation cannot
re-run it, so a parseable reply on an item carrying no close-time bot-authored record admits
nothing. On the comment floor the marker lookup enforces this structurally (no marker
comment, nothing to edit); a native-field handler has no lookup and MUST verify the
close-time unattested record is present on the item's fields before writing the attested
fields — and where the surface was admitted on the audit-trail alternative rather than
automation-only ACLs, presence alone proves nothing (any field-writer can forge a
conforming unattested set): the handler MUST confirm through the audit trail that the bound
automation identity CREATED the close-time record — and that EVERY subsequent revision of
the record fields was likewise written by it: on this path field writes are not
ACL-restricted, so a later non-automation edit of any record field (a hand-edited
`counterfactual` or `effort_band`) makes the record non-conforming — the handler rejects it
for attestation and consumers ignore it on read, exactly as they ignore a foreign-authored
marker comment. Under automation-only ACLs the restriction itself is the authorship proof
for creation and revisions alike.

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
