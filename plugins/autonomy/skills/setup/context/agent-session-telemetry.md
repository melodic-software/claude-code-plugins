# Agent-session telemetry: Claude Code native evidence

The Claude Code records behind the setup skill's agent-session wiring step and the telemetry
contract's "Native agent-surface evidence" section. The
[monitoring page](https://code.claude.com/docs/en/monitoring-usage) owns every event, attribute,
value set, and configuration variable of the export; this file restates only what a binding
depends on.

## Signal the evidence rides

*Claim:* the export's events ride the logs signal, so a binding that needs them sets
`OTEL_LOGS_EXPORTER` as well as `CLAUDE_CODE_ENABLE_TELEMETRY`. The metrics carry only an
aggregate count of decisions for the code-editing tools, with no record per call. *Basis:* the
page's [Quick start](https://code.claude.com/docs/en/monitoring-usage#quick-start),
[Code edit tool decision counter](https://code.claude.com/docs/en/monitoring-usage#code-edit-tool-decision-counter),
and [Events](https://code.claude.com/docs/en/monitoring-usage#events) sections, read as raw
markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry touching the
logs exporter or the code edit decision counter, or a read-time fetch of those sections that no
longer matches this record.

## Resource attributes on every datapoint and event

*Claim:* values set in `OTEL_RESOURCE_ATTRIBUTES` are attached to every metric datapoint and every
event record as well as the resource block, so `autonomy.work_item.url` reaches each signal the
slice joins on. `OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES=false` drops them from datapoint labels,
so a binding that joins metrics on the attribute must not set it to false. *Basis:* the page's
[Multi-team organization support](https://code.claude.com/docs/en/monitoring-usage#multi-team-organization-support)
section, read as raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog
entry touching resource attributes or `OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES`, or a read-time
fetch of that section that no longer matches this record.

## Inbound trace context in headless sessions

*Claim:* `-p` and Agent SDK sessions read `TRACEPARENT` and `TRACESTATE` from the environment, and
with `TRACEPARENT` set each event record carries the inbound trace ID, even with no traces
exporter and no beta flag. The page gives trace IDs to event records only, not to metric
datapoints. Limits:

- With no active interaction span, a record's span ID is the caller's inbound span ID. With beta
  tracing on, records emitted inside a turn carry the interaction span's IDs instead; that case is
  documented, not probed.
- The floor is v2.1.212: before it, records outside an active span carried no trace or span ID.
- Interactive sessions ignore inbound `TRACEPARENT`.

*Basis:* the page's [Traces (beta)](https://code.claude.com/docs/en/monitoring-usage#traces-beta)
section, read as raw markdown, and a probe: Claude Code 2.1.281, 2026-09-23, `claude -p` with
`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=console`, `OTEL_TRACES_EXPORTER=none`, no
beta flag, and `TRACEPARENT` set. 214 of 214 event records carried the inbound trace and span IDs;
a control run without `TRACEPARENT` gave 214 of 214 with none. The Agent SDK half is documented,
not measured. *Verified:* 2026-09-25 (page re-read; probe as of 2026-09-23). *Recheck trigger:* a
Claude Code changelog entry touching
inbound `TRACEPARENT` or event trace correlation, or a read-time fetch of that section that no
longer matches this record.

## Traces stay beta

*Claim:* spans go through the traces exporter only with `CLAUDE_CODE_ENABLE_TELEMETRY=1`,
`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, and an `OTEL_TRACES_EXPORTER` all set; detailed beta
tracing (`ENABLE_BETA_TRACING_DETAILED` with `BETA_TRACING_ENDPOINT`) sends logs and traces to that
endpoint instead. The slice treats spans as optional. *Basis:* the page's
[Traces (beta)](https://code.claude.com/docs/en/monitoring-usage#traces-beta) section, read as
raw markdown. *Verified:* 2026-09-25. *Recheck trigger:* the page drops the beta label from that
section or drops the `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` flag.

## Evidence that a guardrail fired

*Claim:* the `claude_code.tool_decision` event records each tool permission decision, its outcome
in `decision` and its origin in `source`, which separates a configuration decision, a hook
decision, and a user decision. A binding reads it rather than inferring a block from a missing
command. Three limits bind how the evidence is read:

- `config` does not say which settings source or rule matched, and also covers a permission
  prompt request that failed.
- `hook` carries no hook identity. The hook execution event in the page's
  [security-question map](https://code.claude.com/docs/en/monitoring-usage#map-security-questions-to-events)
  adds the hook event and matcher and a count of blocking results, but it joins a decision by
  prompt, not by tool call.
- In a non-interactive `-p` or Agent SDK session, rule matches do not all report `config`: a deny
  rule in the user's personal settings reports `user_reject`, and later matches of a grant made at
  a permission prompt report `user_permanent` or `user_temporary`.

The similarly named `decision_source` belongs to `claude_code.tool_result`, which a rejected call
never produces, so it carries no rejection evidence.

*Basis:* the page's
[Tool decision event](https://code.claude.com/docs/en/monitoring-usage#tool-decision-event) and
[Tool result event](https://code.claude.com/docs/en/monitoring-usage#tool-result-event) sections,
read as raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry
touching `claude_code.tool_decision` or its `source` values, or a read-time fetch of those
sections that no longer matches this record.

## GenAI mirrors on beta spans

*Claim:* the export's beta trace spans carry a few `gen_ai.*` attributes, mostly copies of a
native attribute's value (`gen_ai.system` is a constant). They are consumed as emitted and are not
a pin; the contract records why nothing in that namespace can be pinned yet. *Basis:* the page's
[Traces (beta)](https://code.claude.com/docs/en/monitoring-usage#traces-beta) span attribute
tables, read as raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a read-time fetch of those
tables that no longer matches this record.

## Memory observability gap

*Claim:* the startup load of auto memory's `MEMORY.md` index has no signal documented on the
monitoring or hooks page, so a binding has nothing to show which memory an unattended run began
with. The claim covers those two pages, not what the harness emits. Two neighbors are partly
covered:

- Topic files are read on demand with the standard file tools, per the
  [memory page](https://code.claude.com/docs/en/memory), so those reads surface as ordinary tool
  events. The event names no path by default, so a read is identifiable as a memory read only
  from a tool hook's input or with `OTEL_LOG_TOOL_DETAILS`, which also exports argument content.
  The memory page does not say how memory writes are made.
- Instruction files are reported by the
  [`InstructionsLoaded` hook](https://code.claude.com/docs/en/hooks#instructionsloaded) with path
  and load reason, except an `AGENTS.md` read directly through the Project instructions setting. A
  binding that needs that evidence wraps the hook.

*Basis:* raw-markdown reads of the monitoring page (174,316 bytes) and the hooks page (331,285
bytes). The monitoring page has zero case-insensitive matches for the stem of "memory". The hooks
page has zero matches for `auto memory` or `MEMORY.md`, and its matches for the stem are unrelated
(an MCP memory server, in-memory state, links to the memory page, and the `InstructionsLoaded`
input's instruction-file scope field). *Verified:* 2026-09-23.
*Recheck trigger:* the monitoring page documents a memory event or attribute, or the hooks page
documents a hook event covering auto memory.
