# Telemetry

Normative contract for autonomy telemetry: every execution context an adoption runs, the
interactive session, the CI pipeline, and the autonomous runner, emits standard OpenTelemetry
(OTLP), pinned to the upstream semantic conventions, carrying one contract-owned join
attribute, joined into one causal tree by standard context propagation. The sink is
deliberately out of contract.

## Pillar 1: standard OTLP, pinned semantic conventions

Every execution context emits OTLP pinned to the OpenTelemetry CI/CD and VCS semantic
conventions, release **v1.43.0**. Every contract-authored emission (the writers and adapters
an adoption wires) declares `schema_url: https://opentelemetry.io/schemas/1.43.0`; a native
tool's own emission is consumed as-is: its schema declaration is whatever the tool emits,
and the native-surface principle
forbids rewriting it. A declared schema URL anywhere in a conforming output set must match
the pin. Attribute vocabulary is cited by that registry reference, never copied into this
contract or any conforming document, because the registry owns the names (illustrative citation
only: `cicd.pipeline.run.id` and its sibling pipeline/task attributes, the `vcs.*` change
and revision attributes).

Those conventions are Release Candidate: upstream renames still happen. The pin is exact;
adopting a newer release (including the graduation-to-Stable rename wave) is a reviewed
contract migration owned by the contract home, never a silent upgrade. The migration
trigger is recorded in the capability home's trigger register. Never invent a parallel
schema for a concept the upstream conventions already name.

**Release Candidate status, dated record.** *Claim:* the CI/CD and VCS convention groups are
Release Candidate, not Stable. *Basis:* the upstream conventions repository's own status marker
on the CI/CD document and the Release Candidate badge on every CI/CD and VCS attribute in the
published attribute registry. *Verified:* 2026-09-06. The pinned release **v1.43.0** exists and
is a published release; the upstream latest at that date is **v1.44.0**, and both carry the same
Release Candidate status, so the pin's migration trigger has data but the status claim is
unchanged. *Recheck trigger:* an upstream release whose changelog records a CI/CD or VCS
attribute promoted to Stable, or a Stable badge appearing on either registry page.

## Pillar 2: the work-item join attribute

One custom attribute joins machine telemetry to the work item that caused it:

- **Name:** `autonomy.work_item.url`
- **Value:** the work item's canonical web URL in normalized form: https scheme,
  no trailing slash, no query string, no fragment. String equality is the join operation,
  so this normalization rule is normative.
- **Selection:** the key is always the work item's URL, never a change/PR URL. A change that
  closes N items yields N per-item associations. An agent session keys on the single item it
  was dispatched to work.
- **Scope:** resource-scope on agent-session emission, so session cost and token metrics and
  session spans all carry it; span-scope on CI pipeline and task spans.

Granularity guarantee: conforming autonomous dispatch runs one leased work item per emitting
session/process, and the trigger layer's lease contract is the guarantor. A multi-item batch
session gets session-granular cost only; that limitation is stated, never silently
misattributed.

Known join-epoch limitations: a repository rename or transfer, or a tracker migration,
changes the canonical URL. The join is query-time, so a sink may remap historical values
across such an epoch. A secondary immutable-ID attribute is deferred with a trigger: rename
churn proving material in practice.

Confidentiality: the attribute value inherits the confidentiality class of the repository or
tracker it references. Any sink, artifact, or export carrying it must enforce access controls
at least as strict as the item's home.

Namespace governance: this contract defines no other custom attribute. A sibling capability
contract in this home may define its own additions under the same `autonomy.*` prefix and
governance: reviewed contract changes, no parallel schema for upstream-named concepts.
Minimality binds this contract; it does not forbid governed extension. If the upstream
conventions ever ship a work-item/tracker namespace, this attribute migrates to it under the
same reviewed-migration rule.

## Pillar 3: one causal tree

W3C `traceparent` context propagates trigger → CI → agent session, forming one causal tree
per triggered chain. This is a headless/CI/runner property carried by contract-authored
emissions: each chain leg's wrapper emission (the writers and adapters an adoption wires)
reads inbound trace context from its environment and parents its span accordingly. A native
agent surface that ignores inbound context does
not break the tree: the dispatching wrapper's contract-authored span joins the chain, and
the session's own native emissions attach query-side through the Pillar 2 attribute, which
both surfaces carry. Where a native surface honors inbound context its spans join the tree
directly, but the contract's join stays the Pillar 2 attribute. Interactive contexts are explicitly excluded. The
contract does not promise inbound trace joining for an interactive session, which
deliberately ignores ambient context.

**Native trace-context joining, dated record.** *Claim:* relying on native inbound trace context
was evaluated on 2026-09-25 and not adopted. The agent surface the setup skill wires reads inbound
trace context only in its headless and SDK sessions; its interactive sessions ignore it, and its
tracing is beta and off by default. So the contract keeps the Pillar 2 attribute join as its join.
*Basis:* the setup skill's agent-session wiring records "Inbound trace context in headless
sessions" and "Traces stay beta", whose vendor page was re-read as raw markdown on 2026-09-25.
*Verified:* 2026-09-25. *Recheck trigger:* either of those records' recheck triggers fires.

## Sink binding: out of contract

Where telemetry lands is deployment-owned. The contract names sink classes only:

1. **Existing observability stack.** The org already runs one; emission points at it.
2. **File-artifact free default.** No stack exists: emissions land as OTLP JSON-lines
   artifacts (the OTLP file-exporter encoding), queried on read. Zero standing
   infrastructure, zero cost by default.
3. **Opt-in network backend.** Self-hosted or paid; always explicit opt-in with cost
   surfaced first, never a default.

An adapter for any class must preserve the emitted signals unmodified (schema, attributes,
`schema_url`); class choice, endpoints, and storage are the adopting deployment's. No vendor
is named or privileged by this contract.

## Native-surface principle

Prefer each tool's native telemetry export over reimplementing it. A capability that
re-derives what a native surface already emits is non-conforming; wrap, configure, or
transport native output instead.

## Native agent-surface evidence

What the native-surface principle means for an agent session's own export. This contract names
surface classes; the records for a specific agent surface (which event, which attribute, which
limits, verified against that vendor's documentation) live with the setup skill's agent-session
wiring.

**Guardrail evidence.** Where an agent surface's native export records each tool permission
decision with its outcome and its origin (configuration, hook, or user), a binding that must show a
guardrail fired reads that record rather than inferring a block from a missing command. It also
reads the recorded limits of that evidence before counting on it: an origin that does not name the
matching rule, or that reports the same rule differently in interactive and headless sessions.

**GenAI names are not pinnable, dated record.** *Claim:* the OpenTelemetry GenAI semantic
conventions have moved to their own repository, which has no release, no tag, and no published
schema URL, and whose docs README carries Development status. There is nothing to pin. An agent
surface's `gen_ai.*` attributes are consumed as emitted under Pillar 1 and are not a pin this
contract binds. Adopting the GenAI conventions once released is a reviewed contract migration under
Pillar 1's rule: a known break, never an assumed equivalence. *Basis:* the "Moved" notice at
`docs/gen-ai/README.md` in `open-telemetry/semantic-conventions` (present at the pinned v1.43.0),
and the `open-telemetry/semantic-conventions-genai` repository's release and tag lists, its
README's Schema URL section, and the status marker on its `docs/gen-ai/README.md`. *Verified:*
2026-09-23. *Recheck trigger:* that repository's first tagged release, or its README publishing a
schema URL.

### Agent memory observability: DEFERRED, with a trigger

**The gap:** on the pages its dated absence record searched, the agent surface the setup skill
wires documents no signal for the startup load of its persistent memory index, so a binding has
nothing to show which memory an unattended run began with. The dated absence record, and the
neighboring memory reads that are observable, live with the setup skill's agent-session wiring.

**Why deferred:** a contract-authored memory signal would be a new custom attribute, which Pillar
2's namespace governance admits only through a reviewed contract change, and a wrapper that read
the memory index itself would restate load limits the agent surface's documentation owns.

**Trigger to reconsider:** that absence record's recheck trigger fires.

## Telemetry is not return

Usage measures activity, not return. Nothing in this contract's data answers whether work
was worth doing; the return-accounting convention owns that question, joining its
human-attested records to this telemetry by the Pillar 2 attribute at query time. Telemetry
alone is never presented as return.
