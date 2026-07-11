# Operator setup — Collector daemon

Parent: [`operator-setup.md`](operator-setup.md). Pipeline shape + start commands: [`../otel/otel-collector.yaml`](../otel/otel-collector.yaml) header.

## Keeping the Collector running (always-on)

The Collector is a per-machine singleton — every CC session and worktree connects to
`127.0.0.1:4318`. To never miss startup events, `:4318` must already be listening **before** a
CC session starts. Two mechanisms cooperate:

1. **OS logon daemon (primary)** — starts the Collector at logon, before any terminal or CC
   session. The only mechanism that structurally cannot miss startup events.
2. **SessionStart hook backstop** —
   [`cc-telemetry-ensure.sh`](../../../hooks/cc-telemetry-ensure.sh) runs
   [`../otel/start-collector.sh`](../otel/start-collector.sh) on every session start. Idempotent (no-op when
   `:4318` is already bound), so it revives a dead daemon without double-spawning a live one.

## Keeping the Aspire dashboard running (optional live tail)

The standalone dashboard is **optional** — file capture works without it. The SessionStart hook
([`cc-telemetry-ensure.sh`](../../../hooks/cc-telemetry-ensure.sh)) fire-and-forgets
[`../otel/start-dashboard.sh`](../otel/start-dashboard.sh) on every session start (idempotent;
skips when Docker is absent; disable per machine via `CC_TELEMETRY_DASHBOARD_ENSURE_ENABLED=false`
in `settings.local.json` `env`), so the live telemetry UI (all three signals; in-memory,
bounded by the dashboard's telemetry caps) is normally up without manual action. Manual
start (no session running, or the gate is off):

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/skills/claude-observability/otel/start-dashboard.sh
```

Idempotent wrapper — purpose name `local-otel-dashboard-claude-code` + identification labels
(filter: `docker ps --filter label=local.dev.container.stack=claude-code-observability`).
If an `aspire-dashboard` container is still running, stop/remove it first (the script
prints the exact commands).

The daemon invokes the **binary directly** (`otelcol-contrib --config …`), NOT the bash
`start-collector.sh` — a logon task must not depend on Git Bash being on `PATH` at logon.
`start-collector.sh` stays the hook-path backstop only.

### Prerequisite — pin `CC_OTEL_STORE` to an absolute path

A logon task's working directory is not the repo root (Windows `schtasks` defaults to the
system directory), and the daemon must write ONE store no matter which worktree exists. Set
`CC_OTEL_STORE` to the canonical checkout's **absolute** store dir
(`<repo-root>/.claude/observability/otel`) as a per-machine user environment variable, so the
Collector's `${env:CC_OTEL_STORE}` exporter paths and `cc-otel.sql`'s `getenv('CC_OTEL_STORE')`
views resolve the **same** store from any worktree. With it unset, the daemon would write under
its system-directory CWD and worktree queries would read an empty repo-relative store. The store
directory must exist before the daemon starts — the file exporter does not create parent
directories. Set the env var and create the directory as part of machine setup.

### Windows — per-user Scheduled Task (no admin)

The registration command carries machine-specific absolute paths, so it is **generated from
your machine's paths** (by hand, or by your setup tooling) and never committed —
`hardcoded-path-check` blocks literal machine paths in tracked files. Template (`%USERPROFILE%`
resolves at run time; replace `<repo-root>` with your canonical checkout's absolute path):

```text
schtasks /create /tn "ClaudeCodeOtelCollector" /sc onlogon /rl limited /f /tr ^
  "\"%USERPROFILE%\.otelcol\otelcol-contrib.exe\" --config \"<repo-root>\.claude\skills\claude-observability\otel\otel-collector.yaml\""
```

`/sc onlogon` fires at logon; `/rl limited` runs as the current user (no elevation). With
`CC_OTEL_STORE` set (above) the working directory is irrelevant — every resolved path is
absolute.

**Verify:**

```text
schtasks /query /tn "ClaudeCodeOtelCollector"     :: task registered
schtasks /run   /tn "ClaudeCodeOtelCollector"     :: start now (don't wait for re-logon)
netstat -ano | findstr ":4318"                    :: confirm LISTENING
```

Logon firing itself cannot be tested without re-login — verify manually after the next logon.

**Reversal:**

```text
schtasks /delete /tn "ClaudeCodeOtelCollector" /f
```

### macOS — deferred (recipe)

A `launchd` LaunchAgent at `~/Library/LaunchAgents/<label>.plist` with `RunAtLoad` +
`KeepAlive`; `ProgramArguments` = the `otelcol-contrib` binary + `--config
<repo-root>/${CLAUDE_PLUGIN_ROOT}/skills/claude-observability/otel/otel-collector.yaml`; `CC_OTEL_STORE` via an
`EnvironmentVariables` dict. Load with `launchctl bootstrap gui/$(id -u) <plist>`. Not
implemented (Windows-first).

### Linux — deferred (recipe)

A `systemd --user` unit (`~/.config/systemd/user/cc-otel-collector.service`, `ExecStart=` the
binary + `--config`, `Environment=CC_OTEL_STORE=<abs>`), enabled via `systemctl --user enable
--now cc-otel-collector`; add `loginctl enable-linger "$USER"` to start it at boot rather than
first login. Not implemented (Windows-first).
