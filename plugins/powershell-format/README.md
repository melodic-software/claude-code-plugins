# powershell-format

A Claude Code plugin that formats and lints PowerShell at git pre-commit. On every commit
that stages a `.ps1`, `.psm1`, or `.psd1` file it runs
[PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)'s
`Invoke-Formatter` (formatting in place, then re-staging the result) and
`Invoke-ScriptAnalyzer` (linting), and blocks the commit only on a finding on a line the
commit adds. It covers every author, human or agent, once the entry is installed with
`/powershell-format:setup apply install-git-hooks`.

It uses **your repository's own analyzer settings**. It ships no rules of its own
and runs only when your repo has opted into a `PSScriptAnalyzerSettings.psd1`.

## Behavior

- **Pre-commit entry `powershell-check`.** The staged PowerShell files are rewritten with
  `Invoke-Formatter` and re-staged; the rewritten paths print on stdout. A file that is
  partly staged is refused untouched (`<path>: partly staged; format it or stage it fully,
  then commit`), because re-staging a rewrite would stage its unstaged hunks too. Findings
  print as `<path>:<line>: [<severity>] <rule>: <message>` on stderr and block the commit
  only when the line is one the commit adds.
- **No per-edit hook.** Nothing runs when Claude edits a PowerShell file. A rewrite costs
  more than the 1 s per-batch ceiling (see [Hook budget](#hook-budget-accounting)), and a
  finding reported per edit costs the model attention without helping it finish. Findings
  arrive at commit time instead.
- **Opt-in end-of-turn check.** With `powershell_format_end_of_turn` on, a Stop row runs the
  same check over the uncommitted changes, without rewriting, and hands the findings back
  once per turn. Off by default.
- **Opt-in on a settings file.** PSScriptAnalyzer runs **only on a file a
  `PSScriptAnalyzerSettings.psd1` governs**, found by walking up from the file to the
  repository root and stopping at the closest one. Unlike some formatters,
  PSScriptAnalyzer does not auto-discover its settings, so the entry passes the file
  through. A repo without a settings file is left untouched rather than formatted and
  linted with PSScriptAnalyzer's built-in defaults. A settings file that declares
  `CustomRulePath` is additionally gated on explicit approval. See [Trust model](#trust-model).
- **Installed copies are skipped.** A file under `.githooks/` is never rewritten.
- **Missing tools.** A missing `pwsh` or PSScriptAnalyzer module fails an agent's commit with
  the install command and a one-line skip key (`git -c checks.skipmissing=pwsh commit ...`,
  or `PSScriptAnalyzer`); a person's commit gets a one-line notice and proceeds. `pwsh` is
  resolved from `PATH` and is never downloaded.

## Trust model

The opt-in `PSScriptAnalyzerSettings.psd1` is **executed-adjacent configuration**,
not inert data. A settings file may declare a
[`CustomRulePath`](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer#custom-rules)
pointing at PowerShell rule modules, and PSScriptAnalyzer **loads and runs** those
modules' exported functions during analysis. The entry therefore never runs the
analyzer under such a settings file without an explicit approval: it skips the
run and prints a trust-gate notice. A person's notice names the settings file and the approval marker to
create; an agent commit's notice says the run was skipped and that approval is
yours, without the command that grants it. To approve, review the settings file and every rule module it
references. Treat them with the same trust you give your build and CI
configuration, then create the marker directory using the exact `mkdir -p`
command your notice carries. The marker lives under
`${CLAUDE_PLUGIN_DATA}/trust-approvals` in a Claude Code session, and under the
repository's git directory (`powershell-format/trust-approvals`) when the entry runs
outside one, such as a commit in your terminal; an approval in one place does not cover
the other. The marker is content-addressed over the
repository, the settings file, every file reachable under each declared
`CustomRulePath` entry (recursively for directories), and every repository
file those files reference by string literal (transitively, bounded), so a
change to the settings, to any referenced rule module, or to a file a rule
module loads, including a branch switch that swaps module bytes under an
unchanged settings file, revokes the approval and re-gates the run.
Detection uses PowerShell's restricted data-file parser, not a textual
scan. A settings file that parser cannot read is treated as code-loading
and stays gated. A `CustomRulePath` entry that does not resolve to
hashable content leaves the state unverifiable with no approval route.
When no approval store can be found the gate fails closed and the
run stays skipped. A settings file without
`CustomRulePath` is declarative rule configuration and runs immediately.

## Requirements

- **Bash.** The check scripts run under Bash 3.2+. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code and git hooks can run them under Git Bash.
- **Node.js** on `PATH`. Every handler in `hooks/hooks.json` runs through
  `node hooks/exec-bash.mjs`, which starts the Bash script, and `/powershell-format:setup`
  runs the git-hook installer with it. We do not assume a Claude Code
  install brings Node, so without `node` the hooks do not launch and say nothing.
  Pointer: when deciding whether an install brings Node, fetch
  [setup: Install with npm](https://code.claude.com/docs/en/setup#install-with-npm) live.
  As of: 2026-10-11. Recheck trigger: that section or [System requirements](https://code.claude.com/docs/en/setup#system-requirements) changes which
  install needs Node at runtime.
  [Install Node.js](https://nodejs.org/en/download).
- **jq** on `PATH`. Declared in `prerequisites.json`; the `SessionStart` probe reports it.
  [Install jq](https://jqlang.org/download/).
- **PowerShell 7+** (`pwsh`) on `PATH`
  ([install](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)). The
  plugin probes `pwsh` only; legacy Windows PowerShell 5.1 (`powershell.exe`) is not used. If absent,
  a SessionStart probe reports the missing `pwsh` once per session,
  from `prerequisites.json`, naming `/powershell-format:check`. The probe runs wherever the plugin
  is enabled and `powershell_format_enabled` is not false. `/powershell-format:check` is read-only
  and installs nothing.
- The **PSScriptAnalyzer** module installed
  (`Install-Module PSScriptAnalyzer`).
- A **`PSScriptAnalyzerSettings.psd1`** in your repo. That file is the opt-in.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the plugin's always-on hook is the Stop row. With `powershell_format_end_of_turn` at its
default (false) the `--require-true` gate closes inside the `node` launcher, so a turn end
costs one process (`.performance/ratchets.json` holds that at 1 spawn).

There is no `PostToolBatch` row. A row that rewrites the PowerShell a batch wrote has to start
`pwsh` and load PSScriptAnalyzer, and the measured cost is over the 1 s per-batch ceiling.
Measured on WSL2 Ubuntu (Linux 6.18) with bash 5.3.9, pwsh 7.6.6, PSScriptAnalyzer 1.25.0 and
`node` 24, ten fires each of the row as a prototype launched through `exec-bash.mjs`:

| Batch | Median wall | Min-max |
| --- | --- | --- |
| No `.ps1` in the payload | 0.039 s | 0.035-0.041 s |
| A `Read` of a `.ps1` file, nothing to rewrite | 0.052 s | 0.048-0.058 s |
| One `Edit` of a `.ps1` file that needs a rewrite | 1.03-1.13 s (three runs) | 0.82-1.38 s |

The pre-commit entry over the same single file, rewrite included, measured 0.80 s median
(0.71-0.90 s) with `pwsh` as the only slow part; this host is not the Windows reference host
the convention names, so re-measure there.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install powershell-format@<marketplace>
```

Then verify prerequisites with `/powershell-format:setup check`.

## Configuration

The formatting and linting rules come from the
`PSScriptAnalyzerSettings.psd1` already in your repository, which the entry reads
automatically. To change the rules, edit that file.

Two behavior knobs are exposed as native `userConfig` options:

| Option | Default | Effect |
|--------|---------|--------|
| `powershell_format_enabled` | `true` | Toggle for the end-of-turn check and the session-start probe; set `false` for a clean no-op. |
| `powershell_format_end_of_turn` | `false` | Check the uncommitted changes when a turn ends. |

Set it interactively with `/plugin configure powershell-format@<marketplace>`, or headless
on the install command:

```shell
claude plugin install powershell-format@<marketplace> --config powershell_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `powershell_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED` | Turns the end-of-turn check and the session-start probe on or off. The git pre-commit entry is registered by /powershell-format:setup apply install-git-hooks and is not affected. |
| `powershell_format_end_of_turn` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN` | At the end of each turn, run the pre-commit PSScriptAnalyzer check over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure powershell-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install powershell-format@<marketplace> -s <scope> --config powershell_format_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "powershell-format@<marketplace>": {
         "options": {
           "powershell_format_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
