# Research: Unifying Dev-Session + CI Verification Telemetry via OpenTelemetry (July 2026)

Verified against primary sources 2026-07-17. Method: broad web sweep, then funneled to opentelemetry.io spec pages, open-telemetry GitHub repos, code.claude.com, docs.github.com, vendor pricing pages. Anything not confirmed at a primary source is flagged in the last section.

## Summary

1. OTel CI/CD semantic conventions exist and are at **Release Candidate** (not Stable, not raw experimental): `cicd.*` and `vcs.*` attribute registries, plus CICD span/metric/log conventions, driven by the CI/CD Observability SIG (formed Nov 2023, OTEP #223). First landed in semconv v1.27.0.
2. The vocabulary needed for verification events already exists: `cicd.pipeline.run.id`, `cicd.pipeline.result` (success/failure/timeout/skip), `cicd.pipeline.task.run.result`, `cicd.pipeline.task.type` (build/test/deploy), `vcs.change.id` (PR), `vcs.ref.head.revision` (commit). No work-item-tracker attribute exists in semconv — that join key is a gap you must define yourself.
3. CI-side emission is real but young: `githubreceiver`/`gitlabreceiver` in otelcol-contrib are **alpha** webhook→trace converters; Jenkins has a mature official OTel plugin; `otel-cli` and junit2otlp are experimental community tools. OTLP-to-file with no network backend is a spec'd pattern (OTLP File Exporter, JSON-lines, status **Development**) and the collector `fileexporter` implements it; marketplace actions already ship OTLP trace files as GitHub artifacts.
4. Claude Code natively exports OTel metrics + log events (cost, tokens, tool results) and beta traces; headless `claude -p` inherits W3C `TRACEPARENT`, so CI runs can join a parent pipeline trace. Off by default, standard `OTEL_*` config — free.
5. Query-on-read (OTLP JSON/parquet in files/object storage, DuckDB on demand) is an emerging recognized pattern with real tooling (DuckDB community `otlp` extension, otlp2parquet, ducktel) but no standards-body blessing. Consensus guidance for CI observability is "emit standard OTLP, feed whatever backend you already have" — which favors a **schema-level contract (semconv-aligned attributes) with pluggable sinks**, not a mandated central backend.

## Q1 — OTel CI/CD semantic conventions status

- **SIG**: CI/CD Observability SIG formally launched Nov 2023, based on OTEP #223 ("Introduce semantic conventions for CI/CD observability", merged); OTEP #258 (env-var context propagation) also approved. First conventions merged in **semconv v1.27.0** under `cicd`, `artifacts`, `vcs`, `test`, `deployment` namespaces. Source: https://opentelemetry.io/blog/2025/otel-cicd-sig/ ; OTEP PR: https://github.com/open-telemetry/oteps/pull/223
- **Stability**: the `cicd.*` attribute registry page shows every attribute badged **Release Candidate** (rc), not Stable. Same for active `vcs.*` attributes. Sources: https://opentelemetry.io/docs/specs/semconv/registry/attributes/cicd/ , https://opentelemetry.io/docs/specs/semconv/registry/attributes/vcs/
- **Attributes that exist** (all RC): `cicd.pipeline.name`, `cicd.pipeline.run.id`, `cicd.pipeline.run.state` (pending/executing/finalizing), `cicd.pipeline.result` (success/failure/timeout/skip), `cicd.pipeline.run.url.full`, `cicd.pipeline.task.name`, `cicd.pipeline.task.run.id`, `cicd.pipeline.task.run.result`, `cicd.pipeline.task.run.url.full`, `cicd.pipeline.task.type` (build/test/deploy), `cicd.pipeline.action.name`, `cicd.system.component`, `cicd.worker.*`.
- **Span conventions** (Release Candidate): pipeline-run span (SERVER kind, requires `cicd.pipeline.result`, conditionally `error.type`) and task-run span (INTERNAL kind, requires task name/run.id/result/url). Source: https://opentelemetry.io/docs/specs/semconv/cicd/cicd-spans/ . Metric and log conventions pages also exist: https://opentelemetry.io/docs/specs/semconv/cicd/cicd-metrics/ , https://opentelemetry.io/docs/specs/semconv/cicd/cicd-logs/
- **Falsification**: the claim "CICD semconv is stable" is FALSE as of July 2026 — it is Release Candidate. RC means naming is near-final but breaking renames still happen (see githubreceiver's v1.37.0 alignment renames in Q2).

## Q2 — CI-side OTel emission options

- **githubreceiver (otelcol-contrib)**: official contrib component; **alpha** for traces and metrics. Serves a webhook endpoint consuming `workflow_run`/`workflow_job` events → spans (trace ID derived from run_id+run_attempt); also scrapes VCS metrics via GitHub APIs. Recently realigned to semconv v1.37.0 with breaking attribute renames (`vcs.vendor.name`→`vcs.provider.name` etc.). Source: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/githubreceiver/README.md
- **gitlabreceiver (otelcol-contrib)**: exists, same webhook→trace pattern: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/gitlabreceiver (stability not fetched — assume alpha; flagged below).
- **Jenkins**: official `opentelemetry-plugin` under jenkinsci org — the most mature CI OTel emitter; traces of pipelines/jobs, OTLP/Prometheus exporters. https://github.com/jenkinsci/opentelemetry-plugin
- **otel-cli** (equinix-labs): spans from shell scripts; self-badged **experimental**, last release v0.4.5 (Apr 2024) — usable, low maintenance velocity. https://github.com/equinix-labs/otel-cli
- **junit→OTLP**: `mdelapenya/junit2otlp` (community, xUnit XML → traces+metrics, CI-context-aware attributes): https://github.com/mdelapenya/junit2otlp ; JUnit5 extension `Okeanos/junit-otel-extension`. No official OTel-org test-report converter found.
- **Marketplace actions**: `otel-export-trace-action` and `opentelemetry-upload-trace-artifact` — the latter explicitly writes an **OTLP trace log file and uploads it as a GitHub artifact**, decoupling emission from network export (https://github.com/marketplace/actions/opentelemetry-upload-trace-artifact); also `paper2/github-actions-opentelemetry`. All community-maintained, none official.
- **File-as-artifact without network backend — yes, spec'd**: the OTLP File Exporter spec defines JSON-lines files of OTLP `TracesData`/`MetricsData`/`LogsData` (status **Development**; supplementary to OTLP, not core): https://opentelemetry.io/docs/specs/otel/protocol/file-exporter/ . The collector `fileexporter` (contrib) implements JSON/proto file output with rotation/compression: https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/exporter/fileexporter/README.md . So a CI job can run a tiny collector (or write OTLP JSON directly) and upload the file as a build artifact — zero paid infrastructure.

## Q3 — Claude Code native telemetry

Source: https://code.claude.com/docs/en/monitoring-usage (official).

- **Enable**: `CLAUDE_CODE_ENABLE_TELEMETRY=1` (off by default) + standard `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` / `OTEL_TRACES_EXPORTER` (`otlp`, `console`, `prometheus` for metrics, `none`); standard `OTEL_EXPORTER_OTLP_ENDPOINT/PROTOCOL/HEADERS`, per-signal endpoint overrides, mTLS. Managed via `settings.json` `env` block (MDM-distributable; managed values non-overridable). `otelHeadersHelper` for dynamic auth headers.
- **Signals**: metrics — `claude_code.session.count`, `claude_code.token.usage` (by type/model/agent/skill/plugin), `claude_code.cost.usage` (USD), `claude_code.lines_of_code.count`, `claude_code.commit.count`, `claude_code.pull_request.count`, `claude_code.active_time.total`. Events (logs) — `claude_code.user_prompt`, `claude_code.api_request` (per-request tokens), `claude_code.tool_result`, `claude_code.tool_decision`, plugin/skill/hook/MCP events. **Traces (beta)** via `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`: span tree `claude_code.interaction` → llm_request/hook/tool.
- **Headless/CI**: explicitly supported — non-interactive `claude -p` and the Agent SDK **read `TRACEPARENT`/`TRACESTATE`** from the environment, so session spans nest under a CI pipeline trace; interactive sessions deliberately ignore inbound TRACEPARENT. With enhanced telemetry, spawned Bash subprocesses inherit TRACEPARENT. Note: `OTEL_*` vars are NOT propagated to subprocesses/hooks automatically.
- **No file exporter**: exporters are console/otlp/prometheus only — file output requires a local collector with `fileexporter` (or console capture). This matters for the artifact pattern.

## Q4 — Sink patterns and cost profiles

- **(a) Query-on-read**: recognized emerging pattern with concrete tooling, not a standards-blessed architecture:
  - DuckDB community extension `otlp` — `read_otlp_traces()/read_otlp_logs()/read_otlp_metrics_*()` over local, glob, S3/HTTP/Azure/GCS paths: https://duckdb.org/community_extensions/extensions/otlp (repo: https://github.com/smithclay/duckdb-otlp)
  - `otlp2parquet` (OTLP→parquet): https://github.com/smithclay/otlp2parquet ; `ducktel` (single-binary OTLP receiver → date-partitioned parquet → embedded DuckDB): https://github.com/davidgeorgehope/ducktel
  - Pattern write-up: "Cheap OpenTelemetry lakehouses with parquet, duckdb and Iceberg" https://clay.fyi/blog/cheap-opentelemetry-lakehouses-parquet-duckdb-iceberg/
  - Combined with the OTLP File Exporter spec + CI artifacts, "OTLP files as artifacts, DuckDB on demand" is buildable entirely from free parts and has direct precedent (opentelemetry-upload-trace-artifact does file-as-artifact today).
- **(b) Self-hosted free**: Grafana LGTM stack, SigNoz, Jaeger v2 (collector-based), OpenObserve — all OSS/free; cost is ops burden (a running service, storage, upgrades, auth). SigNoz publishes both Claude Code monitoring and CI/CD observability guides (https://signoz.io/docs/claude-code-monitoring/, https://signoz.io/blog/cicd-observability-with-opentelemetry/), i.e. one OTLP endpoint ingests both streams unchanged.
- **(c) Hosted free tiers** (primary pricing pages): Grafana Cloud Free — 14-day retention, "generous usage limits" (widely reported as 10k metric series / 50GB logs / 50GB traces / 3 users; exact figures behind FAQ — flagged): https://grafana.com/products/cloud/free-tier/ . Honeycomb Free — 20M events/month, 100M metric datapoints/month; Pro from $150/mo: https://www.honeycomb.io/pricing . Datadog CI Visibility is a paid SKU (no meaningful free tier — flagged, not verified at pricing page).
- **Consensus**: vendor and OTel-community guidance (OTel CICD SIG blog, CNCF blog, SigNoz/Dash0/Grafana guides) uniformly frames CI/CD observability as "emit standard OTel from CI, send it to the observability backend you already run" — i.e. treat the backend as deployment-time choice, standardize at the wire/schema level. No source recommends a bespoke CI-only sink.

## Q5 — Correlation attributes

- **Exists in semconv (RC)**: `vcs.change.id` (PR/MR id), `vcs.change.title`, `vcs.ref.head.name/.revision`, `vcs.repository.url.full`, `cicd.pipeline.run.id`, `cicd.pipeline.run.url.full`, `cicd.pipeline.task.run.id`. Older `vcs.repository.change.id` etc. are **deprecated** → renamed forms. Sources as Q1.
- **Gap**: no semconv namespace for work-item / issue-tracker records (no `issue.*`, `work_item.*`, or tracker equivalent found in the registry). Joining telemetry to a tracker item requires a custom attribute (e.g. `com.melodicsoftware.work_item.id`) or riding `vcs.change.id` + tracker↔PR linkage maintained in the tracker. Flag: absence verified only by registry inspection, not an explicit statement in the spec.
- Trace-level correlation across contexts: W3C `TRACEPARENT` env propagation (OTEP #258, approved) + Claude Code's headless TRACEPARENT inheritance means CI pipeline span → agent session spans can be a single trace.

## Q6 — Precedent in AI-agent / dev-tool ecosystems

- **GitHub Copilot**: usage-metrics REST APIs (enterprise/org/user level; adoption, engagement, acceptance, LoC, PR-lifecycle metrics; 28-day report endpoint) — proprietary aggregated API, not OTel: https://docs.github.com/en/rest/copilot/copilot-metrics
- **Cursor**: Admin API + Analytics API for team usage/spend — proprietary REST, not OTel: https://cursor.com/docs/account/teams/analytics-api
- **Claude Code**: the only major agent with native OTel export (Q3).
- **dbt Fusion** emits telemetry with OTel-based tooling (https://docs.getdbt.com/docs/fusion/telemetry) — dev-tool precedent for OTel-native product telemetry.
- **No found precedent** of an ecosystem that unifies interactive-session telemetry and CI verification telemetry under one OTel schema — the combination appears novel; the ingredients (Claude Code OTel + cicd semconv + TRACEPARENT propagation) are all standard.

## Implications for contract design

1. **Standardize at the schema level, not the sink level.** Everything found (RC semconv, alpha receivers, consensus "feed your existing stack") points to: define verification events as OTel signals using `cicd.*`/`vcs.*` RC attributes plus a minimal custom namespace (work-item id, cost, agent identity), and treat transport/backend as per-deployment config. The existing local collector + DuckDB pipeline is then just one conforming sink.
2. **Pin a semconv version in the contract.** Attributes are RC, and real renames shipped as recently as the githubreceiver's v1.37.0 alignment. Record `telemetry.sdk`/schema_url and plan for rename migrations; don't hand-copy attribute lists into docs.
3. **Query-on-read is a legitimate free default for CI.** OTLP File Exporter (JSON lines) + CI artifact upload + DuckDB `otlp` extension gives CI emission with zero standing infrastructure and zero cost; a network OTLP endpoint (self-hosted or hosted free tier) is the opt-in upgrade. Precedent exists for both halves (upload-trace-artifact action; duckdb-otlp/otlp2parquet).
4. **Correlation design**: use `vcs.change.id` + `vcs.ref.head.revision` + `cicd.pipeline.run.id` as the standard join keys; add one custom work-item attribute (semconv has no tracker namespace). Use TRACEPARENT propagation so autonomous-runner and headless-CI agent sessions nest under the pipeline trace — Claude Code supports this natively in `-p` mode.
5. **Three contexts, one contract**: interactive (Claude Code OTel → local collector), CI (workflow-level via githubreceiver webhook or file-artifact pattern + job-level agent spans via TRACEPARENT), autonomous runner (Agent SDK reads TRACEPARENT; same schema). Nothing found forces a central backend; nothing found blocks one later.

## Unverified / flagged claims

- **Latest semconv release number as of July 2026 not pinned** — githubreceiver references alignment with v1.37.0; the registry pages are versionless "latest". Verify exact version at https://github.com/open-telemetry/semantic-conventions/releases before pinning.
- **gitlabreceiver stability level** assumed alpha by analogy; README not fetched.
- **Grafana Cloud free-tier exact quotas** (10k series / 50GB logs / 50GB traces / 3 users) corroborated by multiple secondary sources; the primary page confirms only "generous usage limits, 14-day retention" and hides numbers in an unfetched FAQ.
- **Datadog CI Visibility pricing** (paid, per-committer) not verified at a Datadog page this pass.
- **"No work-item attribute in semconv"** is an absence claim based on registry inspection of cicd/vcs namespaces; a full registry sweep (all namespaces) was not performed.
- **Jaeger v2 / OpenObserve / SigNoz ops-burden characterization** is judgment, not a sourced benchmark.
- **Claude Code traces remain beta** (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`) per current docs — re-check before relying on span shapes; beta features can change without notice.
