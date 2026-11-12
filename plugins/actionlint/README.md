# actionlint

A Claude Code plugin that lints GitHub Actions workflow files with
[actionlint](https://github.com/kjanat/actionlint) at git pre-commit, for every author.
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
  actionlint's embedded-bash ShellCheck and `shell: python` pyflakes integrations are turned off
  at commit time; run the full integrations in CI. For how the integration runs, see
  [actionlint checks: ShellCheck integration for `run:`](https://github.com/rhysd/actionlint/blob/main/docs/checks.md#shellcheck-integration-for-run).
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
- **actionlint** on `PATH`. The linter itself. Absent: see the commit behavior above. Install the
  [kjanat/actionlint](https://github.com/kjanat/actionlint) fork, the release melodic-software CI
  pins: it accepts `$/` refs and `concurrency.queue`, which rhysd/actionlint 1.7.12 rejects. See
  its [install guide](https://github.com/kjanat/actionlint/blob/v1.17.0/docs/install.md); the
  unqualified `actionlint` package in Homebrew core, Scoop and most registries installs upstream.
  A SessionStart probe reports a missing `actionlint` once per session, from
  `prerequisites.json`, and a drifted git-hook entry. `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether
  the binary resolves and installs nothing.

### Hook budget accounting

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md),
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
/plugin install actionlint@melodic-software
```

Then verify prerequisites with `/actionlint:setup check` and register the pre-commit entry with
`/actionlint:setup apply install-git-hooks`.

## Configuration

For actionlint's own configuration file, see
[actionlint configuration: Configuration file](https://github.com/rhysd/actionlint/blob/main/docs/config.md#configuration-file).
Two `userConfig` options tune the hooks themselves:

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

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `actionlint_enabled` | boolean | `true` | Turn the plugin's Claude Code hooks (the opt-in end-of-turn check and the session-start probe) on or off |
| `actionlint_end_of_turn` | boolean | `false` | At the end of each turn, run the pre-commit actionlint check over the workflow lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Off by default. |

### How to set these

Set the options above for `actionlint@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
