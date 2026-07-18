# CI OTLP file-artifact templates

Snippet shapes the telemetry slice wires on the file-artifact free default. Everything below
is surface-class parameterized — `<...>` placeholders are resolved from the binding at wire
time; no org, fleet, or vendor value is baked in. All output lands in ONE artifact directory
per run (`<artifact-dir>`), uploaded as a build artifact; the OTLP JSON encoding uses
lowerCamelCase keys (`resourceSpans`, `schemaUrl`).

## Pipeline-span writer (JSON-lines)

Emit one pipeline/task span per run as a single OTLP JSON line appended to
`<artifact-dir>/pipeline.jsonl` — no dependency beyond a shell and the platform's own run
metadata. When a traced trigger already ran, the inbound `TRACEPARENT`
(`00-<trace-id>-<parent-span-id>-<flags>`) supplies BOTH the shared trace ID and the
`parentSpanId`, so the pipeline span joins the trigger's tree instead of rooting a second
one; with no inbound context, generate a fresh trace ID and omit `parentSpanId`:

```sh
if [ -n "${TRACEPARENT:-}" ]; then
  trace_id="$(printf '%s' "$TRACEPARENT" | cut -d- -f2)"
  parent_field="\"parentSpanId\":\"$(printf '%s' "$TRACEPARENT" | cut -d- -f3)\","
else
  trace_id="<generated 32-hex>"
  parent_field=""
fi
span_id="<generated 16-hex>"
cat >> "<artifact-dir>/pipeline.jsonl" <<JSON
{"resourceSpans":[{"schemaUrl":"https://opentelemetry.io/schemas/1.43.0","resource":{"attributes":[]},"scopeSpans":[{"scope":{"name":"<emitter-name>"},"spans":[{"traceId":"$trace_id","spanId":"$span_id",$parent_field"name":"<pipeline-name>","kind":2,"startTimeUnixNano":"<start-ns>","endTimeUnixNano":"<end-ns>","attributes":[{"key":"cicd.pipeline.run.id","value":{"stringValue":"<run-id>"}},{"key":"autonomy.work_item.url","value":{"stringValue":"<canonical-item-url>"}}]}]}]}]}
JSON
```

The registry pinned by the contract owns the standard attribute names; add the run's
`cicd.*`/`vcs.*` values from platform metadata rather than inventing names.

## Trace-context injection for agent steps

Export W3C context before the headless agent step so its spans join the tree:

```sh
export TRACEPARENT="00-$trace_id-$span_id-01"
```

## Ephemeral per-job collector (agent-session capture)

The agent CLI exports OTLP over the network only, so the free default runs a per-job
collector (single static OSS collector binary) that receives the session's OTLP and writes
JSON-lines into the same artifact directory. Config shape:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 127.0.0.1:4318
exporters:
  file:
    path: <artifact-dir>/session.jsonl
service:
  pipelines:
    metrics: { receivers: [otlp], exporters: [file] }
    logs: { receivers: [otlp], exporters: [file] }
    traces: { receivers: [otlp], exporters: [file] }
```

Start the collector before the agent step, point the session at it
(`OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318`), stop it after. The same binary +
config, with a local store directory instead of `<artifact-dir>`, is the interactive-session
capture shape.

## Session env block (work-item-dispatched)

```sh
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_RESOURCE_ATTRIBUTES=autonomy.work_item.url=<canonical-item-url>
```

## Artifact upload + verification

Upload `<artifact-dir>` with the platform's artifact step, then verify before declaring the
emitting state:

```sh
node "<plugin-root>/skills/setup/scripts/check-emission-conformance.mjs" "<artifact-dir>"
```
