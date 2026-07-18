# Telemetry

Normative contract for autonomy telemetry: every execution context an adoption runs — the
interactive session, the CI pipeline, the autonomous runner — emits standard OpenTelemetry
(OTLP), pinned to the upstream semantic conventions, carrying one contract-owned join
attribute, joined into one causal tree by standard context propagation. The sink is
deliberately out of contract.

## Pillar 1 — standard OTLP, pinned semantic conventions

Every execution context emits OTLP pinned to the OpenTelemetry CI/CD and VCS semantic
conventions, release **v1.43.0**, declaring
`schema_url: https://opentelemetry.io/schemas/1.43.0` on every emission. Attribute
vocabulary is cited by that registry reference, never copied into this contract or any
conforming document — the registry owns the names (illustrative citation only:
`cicd.pipeline.run.id` and its sibling pipeline/task attributes, the `vcs.*` change and
revision attributes).

Those conventions are Release Candidate: upstream renames still happen. The pin is exact;
adopting a newer release (including the graduation-to-Stable rename wave) is a reviewed
contract migration owned by the contract home — never a silent upgrade. The migration
trigger is recorded in the capability home's trigger register. Never invent a parallel
schema for a concept the upstream conventions already name.

## Pillar 2 — the work-item join attribute

One custom attribute joins machine telemetry to the work item that caused it:

- **Name:** `autonomy.work_item.url`
- **Value:** the work item's canonical web URL in normalized form — https scheme,
  no trailing slash, no query string, no fragment. String equality is the join operation,
  so this normalization rule is normative.
- **Selection:** the key is always the WORK ITEM's URL, never a change/PR URL. A change that
  closes N items yields N per-item associations. An agent session keys on the single item it
  was dispatched to work.
- **Scope:** RESOURCE-scope on agent-session emission, so session cost and token metrics and
  session spans all carry it; span-scope on CI pipeline and task spans.

Granularity guarantee: conforming autonomous dispatch runs ONE leased work item per emitting
session/process — the trigger layer's lease contract is the guarantor. A multi-item batch
session gets session-granular cost only; that limitation is stated, never silently
misattributed.

Known join-epoch limitations: a repository rename or transfer, or a tracker migration,
changes the canonical URL. The join is query-time, so a sink MAY remap historical values
across such an epoch. A secondary immutable-ID attribute is deferred with a trigger: rename
churn proving material in practice.

Confidentiality: the attribute value inherits the confidentiality class of the repository or
tracker it references. Any sink, artifact, or export carrying it must enforce access controls
at least as strict as the item's home.

Namespace governance: this contract defines no other custom attribute. A sibling capability
contract in this home MAY define its own additions under the same `autonomy.*` prefix and
governance — reviewed contract changes, no parallel schema for upstream-named concepts.
Minimality binds this contract; it does not forbid governed extension. If the upstream
conventions ever ship a work-item/tracker namespace, this attribute migrates to it under the
same reviewed-migration rule.

## Pillar 3 — one causal tree

W3C `traceparent` context propagates trigger → CI → agent session, forming one causal tree
per triggered chain. This is a headless/CI/runner property: conforming headless agent
surfaces read inbound trace context from their environment; interactive contexts are
explicitly excluded — the contract does not promise inbound trace joining for an interactive
session, which deliberately ignores ambient context.

## Sink binding — out of contract

Where telemetry lands is deployment-owned. The contract names sink CLASSES only:

1. **Existing observability stack** — the org already runs one; emission points at it.
2. **File-artifact free default** — no stack exists: emissions land as OTLP JSON-lines
   artifacts (the OTLP file-exporter encoding), queried on read. Zero standing
   infrastructure, zero cost by default.
3. **Opt-in network backend** — self-hosted or paid; always explicit opt-in with cost
   surfaced first, never a default.

An adapter for any class MUST preserve the emitted signals unmodified (schema, attributes,
`schema_url`); class choice, endpoints, and storage are the adopting deployment's. No vendor
is named or privileged by this contract.

## Native-surface principle

Prefer each tool's native telemetry export over reimplementing it. A capability that
re-derives what a native surface already emits is non-conforming; wrap, configure, or
transport native output instead.

## Telemetry is not return

Usage measures activity, not return. Nothing in this contract's data answers whether work
was worth doing; the return-accounting convention owns that question, joining its
human-attested records to this telemetry by the Pillar 2 attribute at query time. Telemetry
alone is never presented as return.
