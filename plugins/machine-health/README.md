# machine-health

A Claude Code plugin for **workstation health auditing**: OS-specific checks (disk health, OS
updates, security posture, driver state, CISA Known Exploited Vulnerabilities correlation) run
from a versioned catalog, with trend-aware severity, narrow approval-gated remediations, and a
dated markdown report per run. Fail-safe posture throughout: surface issues over silently fixing
them, and every finding carries reproduction commands.

Windows is fully implemented (27 checks, PowerShell 7.x). macOS and Linux are scaffolded as
`not-implemented.md` stubs. On those hosts the skill reports UNKNOWN and stops rather than
pretending coverage.

| Skill | What it does |
|---|---|
| `/machine-health:audit` | Runs the audit. Load catalog + machine overlay, dispatch checks under per-check timeouts, apply trend-aware severity, run approved remediations (non-dry runs), render the dated report, append history. |
| `/machine-health:setup` | Configures this machine. `check` (default) reports the effective catalog overlay, remediation approvals, and pending proposals against the shipped catalog, and its one write refreshes a stale monthly wrapper copy, only on the owner's yes; `apply` writes the machine-local overlay (disable/deprecate/demote checks, register custom ones) and seeds remediation approvals, interactively, or non-interactively with `disable=`/`deprecate=`/`demote=`/`approve=` arguments; `picks` resolves the picks pasted from an audit run's decision page and writes the mutes and approvals the owner confirms; `schedule` creates the monthly unattended checkup task, only on the owner's yes. |

## The audit

Each run dispatches the enabled catalog checks (90s per-check timeout, 15m total budget), collects
schema-validated JSON results, adjusts severity against the last 8 weeks of history, correlates
related findings, and renders `reports/health-<UTC-timestamp>.md` with CRIT/WARN/INFO/OK/UNKNOWN
sections, reproduction commands, and trend deltas. State is append-only (`history.jsonl`);
a run never prompts for elevation: admin-gated checks return UNKNOWN with a `needs_admin` marker,
and the session may offer an optional elevated pass, shown in full, that the owner approves at the
UAC prompt.

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
(`www.cisa.gov`) are the only permitted outbound URLs. Calls routed through
`scripts/windows/lib/Invoke-AllowlistedWeb.ps1` are enforced against that list and logged to the
run log; a call that bypasses the wrapper is neither. No telemetry, no other network calls, no
`Invoke-Expression` on external data.

## Prerequisites

- PowerShell 7.4 or later.
- To run the test suites: Pester 5.x, 5.7.0 or later and below 6.0.
  `skills/audit/tests/Invoke-MachineHealthTests.ps1` caps the major version, and a host with only
  Pester 6 fails the gate.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install machine-health@<marketplace>
```

## Migrating from an in-repo copy

If you previously ran machine-health as an in-repo skill with reports, state, and logs under one
output base (default `Documents\MachineHealth`):

1. Reports can stay put. Set the `report_dir` option to the same folder (or leave unset for the
   default, which is that folder).
2. Move machine state into the plugin data directory so trend history and approvals carry over:
   `<old output base>\state\` → `${CLAUDE_PLUGIN_DATA}\state\` (`history.jsonl`, `latest.json`,
   `approvals.json`). Old logs may stay behind or move to `${CLAUDE_PLUGIN_DATA}\logs\`.
3. `${CLAUDE_PLUGIN_DATA}` is not named `machine-health`; how Claude Code names it is in
   [Environment variables](https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables)
   (as of 2026-10-11; recheck when that section changes how the directory name is derived). A
   `--plugin-dir` session was observed to name it `machine-health-inline`, which that section does
   not cover (basis: [CHANGELOG](CHANGELOG.md) `## [0.7.0]`, first `### Fixed` entry; as of
   2026-10-11; recheck when `/machine-health:setup check` in a `--plugin-dir` session prints a path
   not ending in `-inline`). Run `/machine-health:setup check` to have the resolved path printed rather than guessing it; a state
   root guessed wrong splits the overlay from the state and logs.

## Configuration

One plugin option: `report_dir` (directory), where dated reports land; unset means
`Documents\MachineHealth` under the user profile. Everything else is machine-local state managed
by `/machine-health:setup`. No hooks, no MCP servers.

### Option details

**`report_dir`.** A report file is named for its UTC timestamp, for example
`reports/health-2026-07-12T153327123Z.md`.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `report_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_REPORT_DIR` | Directory where per-run health reports (reports/health-<UTC-timestamp>.md) are written. Leave unset to use the default: Documents\MachineHealth under your user profile. Machine state (history, approvals, logs) is separate and always lives in the plugin data directory. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure machine-health@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure machine-health@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"report_dir": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install machine-health@<marketplace> -s <scope> --config report_dir=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
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

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Tests

A Pester 5.x suite ships with the plugin (`skills/audit/tests/`). Windows-only. It
mocks Win32/MSFT CIM types that resolve only there:

```powershell
pwsh -NoProfile -File plugins/machine-health/skills/audit/scripts/run-tests.ps1
```

`evals/` holds the audit skill's plugin eval suite, the case format `claude plugin eval` runs
(`/evals:plugin-eval` guides a run). Each case states the host and run facts in its prompt and tells
the skill not to run anything, so no case needs Windows or runs a check. The skill's own `skills/audit/evals/evals.json` is the
skill-creator format, which that command does not read.

## License

MIT (SPDX-License-Identifier: MIT).
