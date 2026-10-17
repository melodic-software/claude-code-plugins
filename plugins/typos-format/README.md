
# typos-format

A Claude Code plugin that spell-checks with [typos](https://github.com/crate-ci/typos) at commit
time. Findings arrive when you commit, from a git pre-commit entry that blocks only on a typo in a
line the commit adds, so they reach every author: Claude, other agents and people. Nothing is
reported while Claude edits. An opt-in end-of-turn check hands findings in the uncommitted changes
back to Claude before a turn ends.

The check honors your repository's own typos configuration: typos discovers it from the checked
path, and the plugin's bundled `config/default-typos.toml` (passed with `-c`, so that SHA-shaped
hex is not read as a misspelling) merges with it through `extend-*` keys. Pointer: the Sources
list in [typos' configuration reference](https://github.com/crate-ci/typos/blob/master/docs/reference.md#sources).
As of: 2026-10-01. Recheck trigger: typos changes its config file names or search order.

## Git pre-commit entry

The plugin ships one git-hook entry, `typos-check` (`git-hooks/entries.json`): a pre-commit
check that blocks a commit only on a typo in a line the commit adds, printed as
`<path>:<line>: <message>`. A typo on a line the commit leaves alone never blocks, a partly
staged file is checked as staged, and your config's excludes hold for every path. The entry
runs once `/typos-format:setup apply install-git-hooks [scope=local|shared]` registers it with the
repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this clone;
shared scope commits the copy under `.githooks/typos-format/`. The bundled
`config/default-typos.toml` is copied beside it. `/typos-format:setup check` reports drift, and the
SessionStart probe prints one line when the entry is missing, stale or edited.

When typos is missing, an agent's commit fails with the install command; a person's commit gets a
one-line notice and goes through. `git -c checks.skipmissing=typos commit ...` skips the check
while typos is absent. The placement rules are the check-placement convention in the
marketplace repository.

## End-of-turn check (opt-in)

With `typos_format_end_of_turn` on, a Stop hook runs the same check over the lines changed since
the last commit, untracked files included. Findings go back to Claude with exit 2, so they are
fixed before the turn ends; once a Stop hook has continued the turn it stays quiet, so it blocks at
most once per turn. Off, its default, a turn end costs one process: the node launcher, whose gate
closes before bash starts (`scripts/hook-census.sh`, WSL2 Ubuntu, 2026-10-15, fenced by
`.performance/ratchets.json`). On, a clean work tree measured 19 process creations and execs on the
same host.

## Requirements

- **typos** on `PATH`, installed at the machine level (cargo, Homebrew, Conda, pacman or a
  pre-built binary; [install typos](https://github.com/crate-ci/typos#install)). It is never
  downloaded on the fly. The SessionStart probe reports a missing `typos` once per session from
  `prerequisites.json`.
- **Bash** runs the check (3.2 or newer, so macOS's own bash works). On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows).
- **Node.js** on `PATH` for the Claude Code rows, which launch through `node hooks/exec-bash.mjs`,
  and for the installer the setup skill runs. `/typos-format:check` reports what resolves; it is read-only and installs nothing.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install typos-format@<marketplace>
```

Then verify prerequisites with `/typos-format:setup check`.

## Configuration

The rules themselves are never configured here. They come from the typos
config already in your repository, which the plugin reads automatically. To
change the rules (allowlist a false positive, ignore a pattern), edit that
file.

Two `userConfig` options tune the Claude Code hooks; the git pre-commit entry has none:

| Option | Default | Effect |
|--------|---------|--------|
| `typos_format_enabled` | `true` | Kill switch for the SessionStart probe and the end-of-turn check. The installed git pre-commit entry keeps running. |
| `typos_format_end_of_turn` | `false` | Set `true` to run the pre-commit check over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. |

Set them interactively with `/plugin configure typos-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install typos-format@<marketplace> --config typos_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `typos_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED` | Kill switch for the plugin's Claude Code hooks: the SessionStart probe and drift line, and the opt-in end-of-turn check. On by default. The git pre-commit entry is installed separately and is not affected. |
| `typos_format_end_of_turn` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_END_OF_TURN` | At the end of each turn, run the pre-commit typos check over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Off by default. |

### How to set these

Three supported routes:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure typos-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install typos-format@<marketplace> -s <scope> --config typos_format_enabled=<value>
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
       "typos-format@<marketplace>": {
         "options": {
           "typos_format_enabled": <value>
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
