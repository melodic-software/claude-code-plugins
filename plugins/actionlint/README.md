# actionlint

A Claude Code plugin that lints GitHub Actions workflow files with
[actionlint](https://github.com/rhysd/actionlint) at git pre-commit, for every author.
actionlint only reports, so nothing runs per edit or per batch of tool calls and no finding
reaches Claude while it edits. An opt-in end-of-turn check shows a session its findings before
it commits.

It ships no rules of its own and no binary. It runs the `actionlint` already on your `PATH`.

## Behavior

- **Report only.** The check never rewrites a file. A finding prints as
  `<path>:<line>: <message>` on stderr and exits `1`. A finding about a whole workflow (a job
  with no `runs-on`) carries the line actionlint names for it.
- **Changed lines only.** At commit it blocks only on a finding that sits on a line the commit
  adds. Findings already in the file do not block an unrelated edit.
- **Scoped to workflows.** Only staged files matching `.github/workflows/*.yml` and
  `.github/workflows/*.yaml` are linted. Other YAML is left alone, and files under `.githooks/`
  (installed copies) are skipped.
- **A partly staged file is linted as staged.** The check reads the index, so the lint matches
  what the commit records.
- **External run-block linters disabled (`-shellcheck= -pyflakes=`).**
  actionlint's embedded-bash ShellCheck and `shell: python` pyflakes integrations are turned off.
  Each spawns a subprocess per `run:` block. ShellCheck deadlocks on large blocks under the
  Windows subprocess IPC path in actionlint 1.7.x. Native workflow diagnostics are unaffected;
  run the full integrations in CI.
- **Opt-in end-of-turn check.** With `actionlint_end_of_turn` on, a Stop row runs the same check
  over the uncommitted workflow changes (untracked files included) when a turn ends and hands
  findings back to Claude once per turn. Nothing is rewritten. Off by default.

## Git pre-commit entry

The plugin ships one git-hook entry, `actionlint-check` (`git-hooks/entries.json`). It reaches
every author, not only Claude, once `/actionlint:setup apply install-git-hooks [scope=local|shared]`
registers it with the repository's hook manager (lefthook, husky or plain git hooks). Local scope
stays in this clone; shared scope commits the copy under `.githooks/actionlint/`.
`/actionlint:setup check` reports drift, and the SessionStart probe prints one line when the
entry is missing, stale or edited.

When `actionlint` is missing, an agent's commit fails with the install command; a person's commit
gets a one-line notice and goes through. `git -c checks.skipmissing=actionlint commit ...` skips the
check while actionlint is absent. The placement rules are the check-placement convention in the
marketplace repository.

## Requirements

- **Bash.** The scripts run on Bash 3.2+. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run them under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash and runs the script, and the git-hook installer is a Node script. Absent: the hooks
  do not launch. `/actionlint:setup check` reports it. [Install Node.js](https://nodejs.org/en/download).
- **actionlint** on `PATH`. The linter itself. Absent: see the commit behavior above. See the
  [actionlint install guide](https://github.com/rhysd/actionlint/blob/main/docs/install.md).
  A SessionStart probe reports a missing `actionlint` once per session, from
  `prerequisites.json`, and a drifted git-hook entry. `/actionlint:check` reports whether the
  binary resolves and installs nothing.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the plugin registers no `PostToolUse` or `PostToolBatch` row, so an edit or a batch of tool calls
costs nothing. The Stop row fires on every turn end; with `actionlint_end_of_turn` off (its
default) the launcher's `--require-true` gate closes before bash starts, so it costs one `node`
process. Measured on WSL2 Ubuntu (bash 5.3.9, actionlint 1.7.12, node 24) on 2026-10-15, spawns
from `scripts/hook-census.sh`, wall times over ten runs after one warm-up:

| Run | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| Stop row, `actionlint_end_of_turn` off | not timed | not timed | 1 (the `node` launcher) |
| Pre-commit entry, one staged clean workflow | 0.033 s | 0.027-0.038 s | not counted |

`.performance/ratchets.json` holds the Stop row with the option off at 1 spawn.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install actionlint@<marketplace>
```

Then verify prerequisites with `/actionlint:setup check` and register the pre-commit entry with
`/actionlint:setup apply install-git-hooks`.

## Configuration

actionlint auto-discovers its own `.github/actionlint.yaml` config from your
repository when present. Two `userConfig` options tune the hooks themselves:

- **`actionlint_enabled`** (boolean, default `true`). Kill switch for the plugin's Claude Code
  hooks (the end-of-turn row and the SessionStart probe). It does not govern the git pre-commit
  entry, which `/actionlint:setup apply install-git-hooks` installs and its `decline` action
  turns off for a clone.
- **`actionlint_end_of_turn`** (boolean, default `false`). Set `true` to run the pre-commit check
  over the uncommitted workflow changes when a turn ends; findings go back to Claude once per turn
  so they are fixed before it stops. Nothing is rewritten.

Configure interactively with `/plugin configure actionlint@<marketplace>` or headless at
install time:

```shell
claude plugin install actionlint@<marketplace> --config actionlint_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `actionlint_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED` | Turn the plugin's Claude Code hooks (the opt-in end-of-turn check and the session-start probe) on or off |
| `actionlint_end_of_turn` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN` | At the end of each turn, run the pre-commit actionlint check over the workflow lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Off by default. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure actionlint@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install actionlint@<marketplace> -s <scope> --config actionlint_enabled=<value>
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
       "actionlint@<marketplace>": {
         "options": {
           "actionlint_enabled": <value>
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
