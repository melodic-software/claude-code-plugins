# machine-health

A Claude Code plugin for **workstation health auditing**: OS-specific checks (disk health, OS
updates, security posture, driver state, CISA Known Exploited Vulnerabilities correlation) run
from a versioned catalog, with trend-aware severity, narrow approval-gated remediations, and a
dated markdown report per run. Fail-safe posture throughout: surface issues over silently fixing
them, and every finding carries reproduction commands.

Windows is fully implemented (17 checks, PowerShell 7.x). macOS and Linux are scaffolded as
honest `NOT_IMPLEMENTED` stubs — on those hosts the skill reports UNKNOWN and stops rather than
pretending coverage.

| Skill | What it does |
|---|---|
| `/machine-health:audit` | Runs the audit — load catalog + machine overlay, dispatch checks under per-check timeouts, apply trend-aware severity, run approved remediations (non-dry runs), render the dated report, append history. |
| `/machine-health:setup` | Configures this machine — walks pending proposals, tunes the check catalog via a machine-local overlay, registers custom checks, and seeds remediation approvals. |

## The audit

Each run dispatches the enabled catalog checks (90s per-check timeout, 15m total budget), collects
schema-validated JSON results, adjusts severity against the last 8 weeks of history, correlates
related findings, and renders `reports/health-<UTC-timestamp>.md` with CRIT/WARN/INFO/OK/UNKNOWN
sections, reproduction commands, and trend deltas. State is append-only (`history.jsonl`);
elevation is never prompted for — admin-gated checks return UNKNOWN with a `needs_admin` marker.

Remediations are deliberately narrow (restart a stopped Automatic service, clear aged temp files),
default to **not approved**, and only run when explicitly approved in the machine's
`approvals.json`. First run is always a dry run.

## Where things land

| Location | Contents |
|---|---|
| Report directory (`report_dir` option; default `Documents\MachineHealth`) | `reports/health-<UTC-timestamp>.md` |
| Plugin data directory (`${CLAUDE_PLUGIN_DATA}`, survives updates) | `state/` (history, latest snapshot, approvals), `logs/` (run + remediation + egress logs), `catalog/checks.local.jsonc` (machine overlay), custom check scripts, `TODO.md` proposals |
| `%LOCALAPPDATA%\machine-health\cache` | CISA KEV feed cache (refreshed weekly) |

The shipped check catalog is read-only at runtime; machine-specific tuning (disable, deprecate,
demote cadence, custom checks) lives in the overlay, written by `/machine-health:setup`.

## Network posture

Egress is allowlisted: Microsoft Update endpoints, winget sources, and the CISA KEV feed
(`www.cisa.gov`) are the only permitted outbound URLs, and every outbound call is logged to the
run log. No telemetry, no other network calls, no `Invoke-Expression` on external data.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install machine-health@melodic-software
```

## Migrating from an in-repo copy

If you previously ran machine-health as an in-repo skill with reports, state, and logs under one
output base (default `Documents\MachineHealth`):

1. Reports can stay put — set the `report_dir` option to the same folder (or leave unset for the
   default, which is that folder).
2. Move machine state into the plugin data directory so trend history and approvals carry over:
   `<old output base>\state\` → `${CLAUDE_PLUGIN_DATA}\state\` (`history.jsonl`, `latest.json`,
   `approvals.json`). Old logs may stay behind or move to `${CLAUDE_PLUGIN_DATA}\logs\`.
3. `${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/machine-health`.

## Configuration

One plugin option: `report_dir` (directory) — where dated reports land; unset means
`Documents\MachineHealth` under the user profile. Everything else is machine-local state managed
by `/machine-health:setup`. No hooks, no MCP servers.

## Tests

A Pester 5.7+ suite ships with the plugin (`skills/audit/tests/`). Windows-only — it
mocks Win32/MSFT CIM types that resolve only there:

```powershell
pwsh -NoProfile -File plugins/machine-health/skills/audit/tests/Invoke-MachineHealthTests.ps1
```

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
