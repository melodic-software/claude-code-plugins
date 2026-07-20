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
| Pillar 3 — inbound `traceparent` joining for headless contexts | **Beta-gated.** Default surface ignores an inbound `TRACEPARENT` (fresh root, no parent). With `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` the same probe JOINS: session spans carry the injected `traceId` and parent to the injected span | **Satisfied natively only behind the enhanced-telemetry beta**, whose span shapes the setup slice deliberately does not depend on — the contract-authored wrapper emission remains the stable conforming leg until spans graduate |

## Decision — hybrid, native-first

1. **Session signals (cost, tokens, spans, events): NATIVE emission.** The dispatching
   surface injects the Pillar-2 join attribute through `OTEL_RESOURCE_ATTRIBUTES` at
   launch. No hook re-derives anything the native surface already emits (native-surface
   principle; a re-derivation would be non-conforming).
2. **Causal joining (Pillar 3): contract-authored wrapper emission.** The trigger/CI/runner
   wrapper keeps emitting its own contract-authored span — inheriting inbound `traceparent`
   and carrying the join attribute — because the DEFAULT native session does not join the
   trace, and the beta path that does is explicitly non-load-bearing (the setup slice treats
   spans as optional and never depends on beta span shapes). Native session signals join the
   chain **query-side by the Pillar-2 resource attribute** (both surfaces carry the same
   normalized item URL); a deployment running the enhanced-telemetry beta additionally gets
   direct span parenting today, as a bonus rather than a dependency.
3. **No migration off hooks is pending, because no hook emission exists to migrate**: the
   contract's conforming session path was already native; what this audit adds is the
   empirically proven injection mechanism for the join attribute and the confirmation that
   the wrapper leg cannot be retired yet.
4. **Contract text reconciled in this change**: the telemetry contract's Pillar 3 and the
   setup CI template previously implied that exporting `traceparent` alone joins the agent
   session's spans into the tree — contradicted by the probe. Both now state the
   wrapper-joins / session-attaches-query-side model this audit proves, so an adopter
   following the shipped wiring produces telemetry that matches the contract's words.

## Load-bearing empirical facts (version-pinned)

- `OTEL_RESOURCE_ATTRIBUTES` injection works on Claude Code 2.1.215 (standard OTel SDK env
  var — expected stable, but the injection is contract-load-bearing, so regressions matter).
- Inbound `TRACEPARENT` is not read by 2.1.215 on the DEFAULT surface; with
  `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` the same version reads it and parents session
  spans correctly (probe: injected traceId carried, `claude_code.interaction` parented to
  the injected span).
- No `schemaUrl` declared by 2.1.215 (re-confirms the WP2-era finding on 2.1.211).

## Revisit triggers

- Enhanced telemetry (spans) graduates from beta → plan retiring the wrapper span in favor
  of one native causal tree; until then the beta's inbound-context support is a bonus, not
  a dependency.
- Claude Code starts declaring a `schemaUrl` → re-evaluate against the contract's pin-match
  rule (a declared URL anywhere in a conforming output set MUST match the pin).
- A Claude Code release breaks `OTEL_RESOURCE_ATTRIBUTES` injection → the join attribute has
  no native path; fall back to wrapper-side session wrapping until restored.
