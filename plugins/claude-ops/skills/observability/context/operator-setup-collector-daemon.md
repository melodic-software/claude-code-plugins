# Operator setup — machine-owned telemetry services

Parent: [`operator-setup.md`](operator-setup.md). Pipeline detail:
[`otel-pipeline.md`](otel-pipeline.md).

## Ownership boundary

The plugin reads and maintains Claude Code telemetry; it does not own long-running processes.
Machine provisioning owns both parts of the local telemetry plane:

- the `otelcol-contrib` Windows service and its installed configuration, converged by
  [`Set-OtelCollector`](https://github.com/melodic-software/provisioning/blob/main/common/Provisioning.psm1);
- the standalone Aspire dashboard containers, declared in
  [`local-otel-dashboards.compose.yaml`](https://github.com/melodic-software/provisioning/blob/main/common/local-otel-dashboards.compose.yaml)
  with `restart: always`.

The Collector is a per-machine singleton that listens on loopback (`127.0.0.1:4317` and
`:4318`). The official Windows MSI installs it as a Windows service; provisioning pins the
release, renders the machine configuration under `%ProgramData%`, sets `CC_OTEL_STORE` to the
same absolute store root, and keeps the service automatic and running. This boot-time service
is available before sign-in, so a per-user `ClaudeCodeOtelCollector` scheduled task and a
SessionStart process spawner are both obsolete and must not be created.

The dashboards are optional in-memory viewers. Provisioning publishes the Claude Code instance
on loopback (`http://127.0.0.1:18888`, OTLP gRPC `127.0.0.1:18889`) and lets Docker restart it
with the engine. Claude sessions must not create, replace, or remove these containers.

## Health and repair

Read-only checks do not require elevation:

```powershell
Get-Service -Name otelcol-contrib
Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 4318 -State Listen
docker ps --filter "label=local.dev.container.stack=claude-code-observability"
```

Expected state is a running `otelcol-contrib` service, a loopback listener on `:4318`, and—when
the optional dashboard stack is enabled—a `local-otel-dashboard-claude-code` container.

Lifecycle repair belongs in the provisioning repository. Re-run the host's elevated,
idempotent machine configuration instead of starting plugin-bundled processes. The service
control permissions needed by the explicit retention-prune action are tracked separately in
[`provisioning#125`](https://github.com/melodic-software/provisioning/issues/125).

The current machine implementation is Windows-first. Other operating systems need an equivalent
machine-owned service manager and stable absolute store path; the plugin deliberately does not
install or synthesize those services.
