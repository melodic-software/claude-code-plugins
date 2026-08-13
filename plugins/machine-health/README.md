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
| `/machine-health:setup` | Configures this machine. `check` (read-only, default) reports the effective catalog overlay, remediation approvals, and pending proposals against the shipped catalog; `apply` writes the machine-local overlay (disable/deprecate/demote checks, register custom ones) and seeds remediation approvals — interactively, or non-interactively with `disable=`/`deprecate=`/`demote=`/`approve=` arguments. |

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
3. `${CLAUDE_PLUGIN_DATA}` resolves under `~/.claude/plugins/data/`, in a directory named for the
   plugin's install identity (`machine-health-<marketplace>`, or `machine-health-inline` for a
   `--plugin-dir` session) — not `machine-health`. Run `/machine-health:setup check` to have the
   resolved path printed rather than guessing it; a state root guessed wrong splits the overlay from
   the state and logs.

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

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `report_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_REPORT_DIR` | Directory where per-run health reports (reports/health-<UTC-timestamp>.md, e.g. health-2026-07-12T153327123Z.md) are written. Leave unset to use the default: Documents\MachineHealth under your user profile. Machine state (history, approvals, logs) is separate and always lives in the plugin data directory. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure machine-health@<marketplace>`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install machine-health@<marketplace> --config report_dir=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "machine-health@<marketplace>": {
         "options": {
           "report_dir": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
