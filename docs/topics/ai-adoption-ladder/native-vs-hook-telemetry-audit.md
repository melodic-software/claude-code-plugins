# Native-vs-hook telemetry audit — decision record

Closes the WP2 deferral (#351): which emission source the autonomy telemetry contract
([`plugins/autonomy/reference/telemetry.md`](../../../plugins/autonomy/reference/telemetry.md))
rides on long-term — the native Claude Code OTLP surface, hook/wrapper-authored emission, or a
hybrid. Audited 2026-07-20 against live captures from this machine's collector store
(`otelcol-contrib` service, OTLP file exports); the two decisive probes ran headless sessions
on Claude Code **2.1.215**.

## Field-by-field: native surface vs contract

| Contract requirement | Native surface (empirical, 2.1.215) | Verdict |
|---|---|---|
| Pillar 1 — `schema_url` pin on contract-authored emissions | Native declares NO `schemaUrl` at resource or scope level, on any signal (metrics, traces, logs) | Already handled: native output is consumed as-is per the contract's native-surface clause; the pin binds contract-authored emissions only |
| Pillar 1 — upstream semconv vocabulary | Native emits its own `claude_code.*` vocabulary (metrics `claude_code.session.count` …, spans `claude_code.llm_request` / `claude_code.interaction`, log events `hook_execution_start` / `plugin_loaded`) plus standard resource attrs (`service.name=claude-code`, `service.version`, `host.arch`, `os.*`) | Consumed as-is; no rewrite |
| Pillar 2 — `autonomy.work_item.url` RESOURCE-scope on agent-session emission | **Native honors `OTEL_RESOURCE_ATTRIBUTES`**: a headless run with `OTEL_RESOURCE_ATTRIBUTES=autonomy.work_item.url=<url>` landed the attribute at resource scope on the session's native metrics export | **SATISFIED natively** via environment injection by the dispatching surface — no hook emission needed |
| Pillar 3 — inbound `traceparent` joining for headless contexts | **Native IGNORES an inbound `TRACEPARENT` environment value**: a headless run with a well-formed `TRACEPARENT` env var produced a fresh root `traceId`, no parent | **NOT satisfied natively** — the contract-authored wrapper emission remains required for the causal tree |

## Decision — hybrid, native-first

1. **Session signals (cost, tokens, spans, events): NATIVE emission.** The dispatching
   surface injects the Pillar-2 join attribute through `OTEL_RESOURCE_ATTRIBUTES` at
   launch. No hook re-derives anything the native surface already emits (native-surface
   principle; a re-derivation would be non-conforming).
2. **Causal joining (Pillar 3): contract-authored wrapper emission.** The trigger/CI/runner
   wrapper keeps emitting its own contract-authored span — inheriting inbound `traceparent`
   and carrying the join attribute — because the native session cannot join the trace.
   Native session signals join the chain **query-side by the Pillar-2 resource attribute**
   (both surfaces carry the same normalized item URL), not by trace context.
3. **No migration off hooks is pending, because no hook emission exists to migrate**: the
   contract's conforming session path was already native; what this audit adds is the
   empirically proven injection mechanism for the join attribute and the confirmation that
   the wrapper leg cannot be retired yet.

## Load-bearing empirical facts (version-pinned)

- `OTEL_RESOURCE_ATTRIBUTES` injection works on Claude Code 2.1.215 (standard OTel SDK env
  var — expected stable, but the injection is contract-load-bearing, so regressions matter).
- Inbound `TRACEPARENT` is not read by 2.1.215.
- No `schemaUrl` declared by 2.1.215 (re-confirms the WP2-era finding on 2.1.211).

## Revisit triggers

- Claude Code native telemetry starts reading inbound trace context → plan retiring the
  wrapper span in favor of one native causal tree.
- Claude Code starts declaring a `schemaUrl` → re-evaluate against the contract's pin-match
  rule (a declared URL anywhere in a conforming output set MUST match the pin).
- A Claude Code release breaks `OTEL_RESOURCE_ATTRIBUTES` injection → the join attribute has
  no native path; fall back to wrapper-side session wrapping until restored.
