# biome-format

A Claude Code plugin that rewrites JavaScript, TypeScript, JSX, and JSON with
[Biome](https://biomejs.dev/) in two places: once per batch of tool calls in a Claude Code session,
and again at git pre-commit for every author. Both run `biome check --write`, which applies safe
fixes, formatting, and import sorting, for `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`,
`.cts`, `.json`, and `.jsonc` files. Findings that remain are reported by the pre-commit entry, on
the lines the commit adds; they no longer reach Claude on each edit.

It uses **your repository's own `biome.json`**. It ships no rules of its own and
runs only when your repo has opted into Biome.

## Behavior

- **One rewrite per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the files that `Write`, `Edit` or `MultiEdit` calls in the batch named and
  runs Biome once per config directory over all of them. It prints nothing and exits `0`: no
  finding and no notice goes to Claude or the user. A file that `Read` named is never rewritten.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`), and the launcher's text
    filter takes one string, which cannot cover ten extensions. The script therefore decides in a
    pattern match before any other process starts, so a batch without a Biome file costs the `node`
    launcher and one `bash`.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
    **As of**: 2026-10-15. **Recheck trigger**: that section adds a matcher or an `if` for the
    event, or changes the `tool_calls` fields.
- **Opt-in on `biome.json`.** Biome runs **only when a `biome.json` or
  `biome.jsonc` governs the edited file**, found by walking up from the file to
  the repository root. A repo without a Biome config is left untouched rather
  than rewritten to Biome's built-in defaults, so the plugin never imposes a
  style you did not choose. (The hidden `.biome.json` / `.biome.jsonc` names are
  intentionally not treated as the opt-in: Biome only loads them from 2.4
  onward, so honoring them here would risk reformatting with built-in defaults on
  an older Biome. Use a canonical `biome.json` / `biome.jsonc`.)
- **Config discovery from your repo.** The topmost governing `biome.json` wins, and Biome runs
  from that config's directory with the files named relative to it, so a single repo-root (or
  subtree) config governs files in subdirectories beneath it and nested configs extend it.
  `BIOME_CONFIG_PATH` is unset for the run, so a stray export cannot swap the repo's config.
- **Safe fixes only.** `biome check --write` never applies unsafe fixes, so an unused import stays
  until you remove it; the pre-commit entry reports it.
- **Pre-existing drift is rewritten whole.** The batch payload carries no pre-edit bytes, so a
  file that already drifted from your config is formatted in full, as the pre-commit entry would.
- **Respects your ignores.** Biome honors your config's `files.includes` ignore rules even for an
  explicitly passed path, so a path your config excludes (generated or vendored code) is left
  untouched. Files under `.githooks/` (installed copies) and gitignored files (unless
  `biome_format_lint_gitignored` is set) are skipped.

## Git pre-commit entry

The plugin ships one git-hook entry, `biome-check` (`git-hooks/entries.json`), which rewrites. At
commit it refuses a partly staged Biome file untouched, runs `biome check --write` over the staged
files, re-stages what changed, and blocks the commit only on a finding Biome still reports on a
line the commit adds (errors, and warnings via `--error-on-warnings`), printed as
`<path>:<line>: <message>`. It reaches every author, not only Claude, once
`/biome-format:setup apply install-git-hooks [scope=local|shared]` registers it with the
repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this clone;
shared scope commits the copy under `.githooks/biome-format/`. `/biome-format:setup check` reports
drift, and the SessionStart probe prints one line when the entry is missing, stale or edited.

Biome comes from the governing config directory's `node_modules/.bin`, else the repo root's, else
`PATH`. When it is missing, an agent's commit fails with the install command; a person's commit
gets a one-line notice and goes through. `git -c checks.skipmissing=biome commit ...` skips the
check while biome is absent. The placement rules are the check-placement convention in the
marketplace repository.

An opt-in Stop row (`biome_format_end_of_turn`) runs the same check over the uncommitted changes
at the end of a turn, without rewriting, and hands findings back to Claude once per turn.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash. A missing `node` is a hook launch error, not a skip notice.
- **jq** on `PATH`. Reads the file paths from the `PostToolBatch` payload. Absent: the batch row
  does nothing, and the SessionStart probe reports it. [Install jq](https://jqlang.org/download/).
- **Biome** available to the repo. Installed in the repo's `node_modules`
  (the hook runs `node_modules/.bin/biome`) or on `PATH`. Biome is never
  downloaded on the fly; if it is not present while a Biome config governs the
  repo, the batch row skips the file.
  **Biome 2.x is recommended** (tested against 2.5.15): the hooks pass `--write`,
  `--error-on-warnings`, `--reporter=concise` and `--no-errors-on-unmatched`, and on much older
  releases those flags may be absent.
- A **`biome.json`** or **`biome.jsonc`** in the repo, the opt-in.

A `SessionStart` probe reports a missing Biome binary before the first edit, and a drifted
git-hook entry. It reads the tool's id, check and install hints from `prerequisites.json`,
resolves `biome` on `PATH` or as `node_modules/.bin/biome` walking up at most eight directories
from the session cwd, does not run when `biome_format_enabled` is `false`, and installs nothing. It
does not look for a `biome.json`, so it reports a missing Biome in every repository where the
plugin is enabled, including one that never opted in.

The hook scripts run on Bash 3.2+.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch of every
session. Measured on WSL2 Ubuntu (bash 5.3.9, Biome 2.5.15 behind a `node` launcher script like
npm's, node 24) on 2026-10-15, with the row launched as `hooks.json` registers it, ten fires per
case; spawns are from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| No Biome file in the payload | 0.029 s | 0.027-0.036 s | 3 (the `node` launcher and one `bash`) |
| A `Read` of a `.ts` file, nothing to rewrite | 0.029 s | 0.026-0.034 s | 6 |
| One `Edit` of a `.ts` file that needs a rewrite | 0.091 s | 0.086-0.103 s | 16 |

The ceiling for a per-batch formatter row is 1 s median per fire. Fences:
`.performance/ratchets.json` holds the no-Biome-file row at 3 spawns, and the Stop row with
`biome_format_end_of_turn` off (its default) at 1 spawn.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install biome-format@<marketplace>
```

Then verify prerequisites with `/biome-format:setup check` or `/biome-format:check`.

## Configuration

The formatting rules come from the `biome.json` already in your repository, which
the plugin reads automatically. To change the rules, edit that file.

Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `biome_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `biome_format_lint_gitignored` | `false` | Set `true` to rewrite a file the repository gitignores. Off by default. |
| `biome_format_end_of_turn` | `false` | Set `true` to run the pre-commit check over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. Nothing is rewritten. |

Set them interactively with `/plugin configure biome-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install biome-format@<marketplace> --config biome_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `biome_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED` | After each batch of tool calls, run Biome check --write over the JavaScript, TypeScript and JSON files it wrote |
| `biome_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_LINT_GITIGNORED` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `biome_format_end_of_turn` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN` | At the end of each turn, run the pre-commit Biome check over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Three supported routes:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure biome-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install biome-format@<marketplace> -s <scope> --config biome_format_enabled=<value>
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
       "biome-format@<marketplace>": {
         "options": {
           "biome_format_enabled": <value>
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
