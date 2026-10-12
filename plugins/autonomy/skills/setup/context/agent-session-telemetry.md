# Agent-session telemetry: Claude Code native evidence

The Claude Code records behind the setup skill's agent-session wiring step and the telemetry
contract's "Native agent-surface evidence" section. The
[monitoring page](https://code.claude.com/docs/en/monitoring-usage) owns every event, attribute,
value set, and configuration variable of the export. Each record below states what a binding does
and where to read the specific it depends on; a binding that needs the specific fetches it from the
pointer.

## Signal the evidence rides

A binding that needs per-call evidence exports events as well as metrics, so it sets the exporter
for the signal events ride beside `CLAUDE_CODE_ENABLE_TELEMETRY`.

- **Pointer**: when choosing which exporters a binding sets, fetch
  <https://code.claude.com/docs/en/monitoring-usage#events> and
  <https://code.claude.com/docs/en/monitoring-usage#code-edit-tool-decision-counter> live.
- **As of**: 2026-10-11
- **Recheck trigger**: a Claude Code changelog entry touching the logs exporter or the code edit
  decision counter, or either section is renamed or removed.

## Resource attributes on every datapoint and event

A binding carries `autonomy.work_item.url` in `OTEL_RESOURCE_ATTRIBUTES`, and one that joins
metrics on that attribute never sets `OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES=false`.

- **Pointer**: when checking which signals carry resource attributes and what that variable
  changes, fetch <https://code.claude.com/docs/en/monitoring-usage#multi-team-organization-support>
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: a Claude Code changelog entry touching resource attributes or
  `OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES`, or that section is renamed or removed.

## Inbound trace context in headless sessions

The slice's join is `autonomy.work_item.url`, never inbound trace context. Where a dispatched
headless session receives `TRACEPARENT`, its event records may carry the caller's trace, which a
query can use but the binding does not depend on.

Probe observation (ours): on Claude Code 2.1.281, 2026-09-23, `claude -p` with
`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=console`, `OTEL_TRACES_EXPORTER=none`, no
beta flag, and `TRACEPARENT` set gave 214 of 214 event records carrying the inbound trace and span
IDs; a control run without `TRACEPARENT` gave 214 of 214 with none. Agent SDK and interactive
sessions were not probed.

- **Pointer**: when a binding needs to know which session kinds read inbound context, from which
  version, and which span ID a record carries, fetch
  <https://code.claude.com/docs/en/monitoring-usage#traces-beta> live. The probe's evidence is in
  [pull request 4414](https://github.com/melodic-software/claude-code-plugins/pull/4414).
- **As of**: 2026-10-11 (page); 2026-09-23 (probe)
- **Recheck trigger**: a Claude Code changelog entry touching inbound `TRACEPARENT` or event trace
  correlation, or that section is renamed or removed.

## Traces stay beta

The slice treats spans as optional and never depends on beta span shapes.

- **Pointer**: when a binding wires spans, fetch
  <https://code.claude.com/docs/en/monitoring-usage#traces-beta> live for the variables spans need.
- **As of**: 2026-10-11
- **Recheck trigger**: the page drops the beta label from that section or drops the
  `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` flag.

## Evidence that a guardrail fired

A binding reads the `claude_code.tool_decision` event as evidence that a guardrail fired, rather
than inferring a block from a missing command. It does not attribute a decision to one settings
rule or one hook from that event alone, and it takes no rejection evidence from
`claude_code.tool_result`.

- **Pointer**: when reading what the decision event's fields can and cannot tell, how session kinds
  differ in what they report, and how the hook execution event joins, fetch
  <https://code.claude.com/docs/en/monitoring-usage#tool-decision-event>,
  <https://code.claude.com/docs/en/monitoring-usage#tool-result-event>, and
  <https://code.claude.com/docs/en/monitoring-usage#map-security-questions-to-events> live.
- **As of**: 2026-10-11
- **Recheck trigger**: a Claude Code changelog entry touching `claude_code.tool_decision` or its
  `source` values, or any of those sections is renamed or removed.

## GenAI mirrors on beta spans

The slice consumes any `gen_ai.*` span attributes as emitted and never pins them; the contract
records why nothing in that namespace can be pinned yet.

- **Pointer**: when a binding reads span attributes, fetch
  <https://code.claude.com/docs/en/monitoring-usage#traces-beta> live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section's span attribute tables are renamed or removed.

## Memory observability gap

Our reading: the startup load of auto memory's `MEMORY.md` index has no signal documented on the
monitoring or hooks page, so a binding has nothing to show which memory an unattended run began
with. The claim covers those two pages, not what the harness emits. A binding that needs evidence
of instruction-file or memory-file reads wraps the hooks that report them.

Basis: raw-markdown reads of the monitoring page (174,316 bytes) and the hooks page (331,285
bytes) on 2026-09-23. The monitoring page has zero
case-insensitive matches for the stem of "memory". The hooks page has zero matches for
`auto memory` or `MEMORY.md`, and its matches for the stem are unrelated (an MCP memory server,
in-memory state, links to the memory page, and the `InstructionsLoaded` input's instruction-file
scope field). The memory page does not say how memory writes are made.

- **Pointer**: when checking whether that coverage changed, fetch
  <https://code.claude.com/docs/en/monitoring-usage#events>,
  <https://code.claude.com/docs/en/hooks#instructionsloaded>, and
  <https://code.claude.com/docs/en/memory#auto-memory> live.
- **As of**: 2026-10-11 (pointer); 2026-09-23 (reading)
- **Recheck trigger**: the monitoring page documents a memory event or attribute, or the hooks page
  documents a hook event covering auto memory.
