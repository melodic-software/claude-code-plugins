# OTEL pipeline — collector, store, Aspire dashboard

Config: [../otel/otel-collector.yaml](../otel/otel-collector.yaml). Emission env profile:
[operator-setup-emission-privacy.md](operator-setup-emission-privacy.md) "Emission profile". Read routing: [read-routing.md](read-routing.md).

## Pipeline

```text
Claude Code (CLI) ── OTLP http://127.0.0.1:4318 ──▶ otelcol-contrib (per-machine singleton)
   ├─ file exporter → $CC_OTEL_STORE/{cc-logs,cc-metrics,cc-traces}.json  (persistent)
   │     └─ DuckDB via ../otel/cc-otel.sql
   └─ otlp_grpc → Aspire standalone dashboard :18889  (all 3 signals — optional live UI)
```

All three signals fan out to Aspire (in-memory live tail, bounded by the dashboard's built-in
telemetry caps; restart resets it). DuckDB stays the persistent SSOT.

## Starting services (manual — no scheduler required)

**Collector** (required for OTEL capture):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/skills/observability/otel/start-collector.sh
```

Idempotent — no-op when `:4318` already listening. SessionStart hook
(`.claude/hooks/cc-telemetry-ensure.sh`) runs the ensure script on each CC session start
as a backstop (hooks cite the `scripts/start-collector.sh` public facade, which delegates
to the private `otel/` backend — see `skill/encapsulation.md` "CI / git-hook consumption — entry surface, not internals").

**Aspire dashboard** (optional — live telemetry UI):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/skills/observability/otel/start-dashboard.sh
```

Browse `http://localhost:18888`. Container: `local-otel-dashboard-claude-code`.

After changing `otel-collector.yaml`: stop `otelcol-contrib`, then re-run `start-collector.sh`.

Optional always-on logon Scheduled Task recipes exist in [operator-setup.md](operator-setup.md)
for operators who want capture before first terminal — **not required**; hook backstop + manual
start are sufficient.

## Store location

| Variable | Role |
|---|---|
| `CC_OTEL_STORE` | Absolute path to `.claude/observability/otel` (recommended — queries work from any worktree) |
| Fallback | Repo-relative `.claude/observability/otel` when unset (run DuckDB from repo root) |

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
