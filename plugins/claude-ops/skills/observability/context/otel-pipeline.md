# OTEL pipeline — collector, store, Aspire dashboard

Machine config:
[`common/otel-collector.yaml`](https://github.com/melodic-software/provisioning/blob/main/common/otel-collector.yaml).
Emission env profile: [operator-setup-emission-privacy.md](operator-setup-emission-privacy.md)
"Emission profile". Read routing: [read-routing.md](read-routing.md).

## Pipeline

```text
Claude Code (CLI) ── OTLP http://127.0.0.1:4318 ──▶ otelcol-contrib (per-machine singleton)
   ├─ file exporter → $CC_OTEL_STORE/{cc-logs,cc-metrics,cc-traces}.json  (persistent)
   │     └─ DuckDB via ../otel/cc-otel.sql
   └─ otlp_grpc → Aspire standalone dashboard :18889  (all 3 signals — optional live UI)
```

All three signals fan out to Aspire (in-memory live tail, bounded by the dashboard's built-in
telemetry caps; restart resets it). DuckDB stays the persistent SSOT.

## Service ownership and health

The Collector and dashboards are machine-owned, not Claude-session processes. Provisioning keeps
the `otelcol-contrib` Windows service automatic and running from boot, and converges the dashboard
Compose stack with Docker's `restart: always` policy. Do not create per-user scheduled tasks or
SessionStart hooks to spawn either component.

Check the required Collector listener:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/net-probe.sh"
port_status 4318
```

Check the optional dashboard:

```bash
curl --fail --silent http://127.0.0.1:18888/api/telemetry/resources >/dev/null
```

Browse `http://127.0.0.1:18888`. Container:
`local-otel-dashboard-claude-code`. If either component is unhealthy, follow
[operator-setup-collector-daemon.md](operator-setup-collector-daemon.md); lifecycle repair belongs
to the provisioning repository.

## Store location

| Variable | Role |
|---|---|
| `CC_OTEL_STORE` | Absolute machine store path set by provisioning (queries work from any worktree) |
| Fallback | Repo-relative `.claude/observability/otel` when unset (development-only) |

Files are gitignored per-developer-local. Content capture (prompts, API bodies) is opt-in via
`.claude/settings.local.json` — see operator-setup "Privacy consequence".

## Health checks

| Check | How |
|---|---|
| Collector listening | `127.0.0.1:4318` bound |
| Store present | `$CC_OTEL_STORE/cc-logs.json` (and siblings after first export) |
| `cc_spans` views | Bind after first trace batch; empty/missing `cc-traces.json` skips view (`.bail off` in init) |
| Aspire up | `curl -s http://localhost:18888/api/telemetry/resources` |

## Privacy

Read [privacy.md](privacy.md) before surfacing OTEL content in reports. The OTEL store can hold
full prompts and API bodies when content keys are on — never echo verbatim into user-visible
output unless the task explicitly requires it.
