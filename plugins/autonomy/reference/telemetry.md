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
directly; relying on that is a recorded migration trigger, not an assumption. Interactive contexts are explicitly excluded. The
contract does not promise inbound trace joining for an interactive session, which
deliberately ignores ambient context.

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

## Claude Code's native export

An agent session on Claude Code emits through the harness's own OpenTelemetry export. The
[monitoring page](https://code.claude.com/docs/en/monitoring-usage) owns every event, attribute,
value set, and configuration variable of that export; this contract restates only what a binding
depends on, in the records below. The export's events ride the logs signal: a binding that needs
them sets `OTEL_LOGS_EXPORTER` as well as `CLAUDE_CODE_ENABLE_TELEMETRY`, because metrics alone
carry none of this evidence.

**Evidence that a guardrail fired, dated record.** *Claim:* the `claude_code.tool_decision` event
records each tool permission decision, its outcome in `decision` and its origin in `source`,
which separates a configuration decision, a hook decision, and a user decision. That is the native
evidence that a guardrail fired, so a binding reads it rather than inferring a block from a
missing command, as the native-surface principle already requires. Three limits bind how the
evidence is read. `config` does not say which settings source or rule matched, and also covers a
permission prompt request that failed. `hook` carries no hook identity; the hook execution event
in the page's
[security-question map](https://code.claude.com/docs/en/monitoring-usage#map-security-questions-to-events)
adds the hook event and matcher and a count of blocking results, but it joins a decision by prompt, not by tool
call. In a non-interactive `-p` or Agent SDK session, rule matches do not all report `config`: a
deny rule in the user's personal settings reports `user_reject`, and later matches of a grant
made at a permission prompt report `user_permanent` or `user_temporary`. The similarly named
`decision_source` belongs to `claude_code.tool_result`, which a rejected call never produces, so
it carries no rejection evidence. *Basis:* the page's
[Tool decision event](https://code.claude.com/docs/en/monitoring-usage#tool-decision-event) and
[Tool result event](https://code.claude.com/docs/en/monitoring-usage#tool-result-event) sections,
read as raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry
touching `claude_code.tool_decision` or its `source` values, or a read-time fetch of those sections that no
longer matches this record.

**Inbound trace context, dated record.** *Claim:* Pillar 3's migration trigger has data. In `-p`
and Agent SDK sessions the export reads an inbound `TRACEPARENT`, parents its interaction span on
the caller's span, and stamps its event records with the caller's trace even when no traces
exporter is set; interactive sessions ignore it. The page records different stamping before
v2.1.214, so a binding relying on it requires v2.1.214 or later. Relying on it remains
Pillar 3's reviewed migration and is not made here. *Basis:* the page's
[Traces (beta)](https://code.claude.com/docs/en/monitoring-usage#traces-beta) section, read as raw
markdown. *Verified:* 2026-09-23. *Recheck trigger:* the Pillar 3 migration is taken up, or a
read-time fetch of that section that no longer matches this record.

**GenAI names are not pinnable, dated record.** *Claim:* the OpenTelemetry GenAI semantic
conventions have moved to their own repository, which has no release, no tag, and no published
schema URL, and whose docs README carries Development status. There is nothing to pin. The
harness's emission is consumed as-is under Pillar 1, and the few `gen_ai.*` attributes on its beta
trace spans, mostly copies of a native attribute's value, are not a pin this contract binds.
Adopting the GenAI conventions once released is a reviewed contract migration under Pillar 1's
rule: a known break, never an assumed equivalence. *Basis:* the "Moved" notice at
`docs/gen-ai/README.md` in `open-telemetry/semantic-conventions` (present at the pinned v1.43.0);
the [semantic-conventions-genai](https://github.com/open-telemetry/semantic-conventions-genai)
repository's release and tag lists, its README's Schema URL section, and the status marker on its
`docs/gen-ai/README.md`. *Verified:* 2026-09-23. *Recheck trigger:* that repository's first tagged
release, or its README publishing a schema URL.

### Memory observability: DEFERRED, with a trigger

**The gap:** the startup load of auto memory's `MEMORY.md` index has no signal documented on the
monitoring or hooks page, so a binding has nothing to show which memory an unattended run began
with. Two neighbors are partly covered. Topic files are read on demand with the standard file
tools, per the [memory page](https://code.claude.com/docs/en/memory), so those reads surface as
ordinary tool events; the event names no path by default, so a read is identifiable as a memory
read only from a tool hook's input or with the page's tool-detail flag, which also exports argument
content. That page does not say how memory writes are made. Instruction files are
reported by the [`InstructionsLoaded` hook](https://code.claude.com/docs/en/hooks#instructionsloaded)
with path and load reason, except an `AGENTS.md` read directly through the Project instructions
setting, and a binding that needs that evidence wraps the hook.

**Absence record.** *Claim:* the monitoring page documents no memory event or attribute, and the
hooks page documents no hook event for auto memory. The claim covers those two pages, not what the
harness emits. *Basis:* raw-markdown reads of the monitoring page (174,316 bytes) and the hooks
page (331,285 bytes). The monitoring page has zero case-insensitive matches for the stem of
"memory". The hooks page has zero matches for `auto memory` or `MEMORY.md`, and its matches for
the stem are unrelated (an MCP memory server, in-memory state, links to the memory page).
*Verified:* 2026-09-23. *Recheck trigger:* the monitoring page documents a memory event or
attribute, or the hooks page documents a hook event covering auto memory.

**Why deferred:** a contract-authored memory signal would be a new custom attribute, which Pillar
2's namespace governance admits only through a reviewed contract change, and a wrapper that read
`MEMORY.md` itself would restate the harness's load limits, which the memory page owns.

**Trigger to reconsider:** the absence record's recheck trigger fires.

## Telemetry is not return

Usage measures activity, not return. Nothing in this contract's data answers whether work
was worth doing; the return-accounting convention owns that question, joining its
human-attested records to this telemetry by the Pillar 2 attribute at query time. Telemetry
alone is never presented as return.
