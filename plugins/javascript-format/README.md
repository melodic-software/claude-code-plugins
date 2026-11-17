# javascript-format

A Claude Code plugin that formats and lints JavaScript, TypeScript, JSX and JSON with
[Biome](https://biomejs.dev/), as two separate concerns, wherever your repository has opted into
Biome. Formatting runs once per batch of tool calls in a Claude Code session and again at git
pre-commit for every author; linting reports at pre-commit, on the lines the commit adds. No lint
fix runs in either place, and no finding reaches Claude on each edit. Both cover `.ts`, `.tsx`,
`.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.json` and `.jsonc` files.

The hooks run only the shipped **Biome adapter**, when a `biome.json` or `biome.jsonc` governs the
file: `biome check --write --linter-enabled=false` for format (the formatter and the assist actions
your config enables, import sorting by default), `biome lint` for lint. A repository without one is
left untouched, and `/javascript-format:setup check` reports the concern unresolved.

The hooks never run a command from your typescript, javascript or json record
(`.claude/ecosystems/<id>.yaml`, the ecosystem-commands contract in the marketplace repository).
That record names any formatter and linter you use, and `/toolchain:lint` and `/toolchain:check`
run it when you ask.

The plugin ships no rules of its own.

## Behavior

- **One format per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the files that `Write`, `Edit` or `MultiEdit` calls in the batch named and
  runs the Biome adapter once per config directory over all of them. It prints nothing and exits
  `0`: no finding and no notice goes to Claude or the user. A file that `Read` named is never
  rewritten.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`), and the launcher's text
    filter takes one string, which cannot cover ten extensions. The script therefore decides in a
    pattern match before any other process starts, so a batch without a Biome file costs the `node`
    launcher and one `bash`.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
- **Opt-in on `biome.json`.** The adapter runs **only when a `biome.json` or `biome.jsonc` governs
  the edited file**, found by walking up from the file to the repository root. A repo without a
  Biome config is left untouched rather than rewritten to Biome's built-in defaults. (The hidden
  `.biome.json` / `.biome.jsonc` names are intentionally not treated as the opt-in: Biome only
  loads them from 2.4 onward, so honoring them here would risk reformatting with built-in defaults
  on an older Biome. Use a canonical `biome.json` / `biome.jsonc`.)
- **Config discovery from your repo.** The topmost governing `biome.json` wins, and Biome runs
  from that config's directory with the files named relative to it, so a single repo-root (or
  subtree) config governs files in subdirectories beneath it and nested configs extend it.
  `BIOME_CONFIG_PATH` is unset for the run, so a stray export cannot swap the repo's config.
- **Format only.** The linter is off for the format run, so no lint fix applies, safe or unsafe;
  the `lint` entry reports what it finds. Assist actions your config turns off stay off.
  - **Pointer**: when deciding what each flag applies, fetch
    [CLI: biome check](https://biomejs.dev/reference/cli/#biome-check) live.
- **Pre-existing drift is rewritten whole.** The batch payload carries no pre-edit bytes, so a
  file that already drifted from your config is formatted in full, as the pre-commit entry would.
- **Respects your ignores.** Biome honors your config's `files.includes` ignore rules even for an
  explicitly passed path, so a path your config excludes (generated or vendored code) is left
  untouched. Files under `.githooks/` (installed copies) and gitignored files (unless
  `javascript_format_lint_gitignored` is set) are skipped.

## Git pre-commit entries

The plugin ships two git-hook entries (`git-hooks/entries.json`):

- `format` rewrites. At commit it refuses a partly staged Biome file untouched, runs the resolved
  format command over the staged files, and re-stages what changed.
- `lint` reports. It runs the resolved lint command and blocks the commit only on a finding on a
  line the commit adds (errors, and warnings via `--error-on-warnings`), printed as
  `<path>:<line>: <message>`. A linter that exits non-zero with no such line, such as Biome
  refusing a config it cannot parse, fails the commit and shows its output.

They reach every author, not only Claude, once
`/javascript-format:setup apply install-git-hooks [scope=local|shared]` registers them with the
repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this clone;
shared scope commits the copies under `.githooks/javascript-format/`. `/javascript-format:setup
check` reports drift, including a copy of the earlier single `biome-check` entry, which that action
retires; a decline of `biome-check` carries to both.

Biome comes from a `node_modules/.bin` the repository does not commit, walking up from the file,
else `PATH`. When it is missing, an agent's commit fails with the install command; a person's commit
gets a one-line notice and goes through. `git -c checks.skipmissing=biome commit ...` skips the
entry while biome is absent. The placement rules are the check-placement convention in the
marketplace repository.

An opt-in Stop row (`javascript_format_end_of_turn`) runs the `lint` entry over the uncommitted
changes at the end of a turn and hands findings back to Claude once per turn.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash. A missing `node` is a hook launch error, not a skip notice.
- **jq** on `PATH`. Reads the file paths from the `PostToolBatch` payload. Absent: the batch row
  does nothing, and the SessionStart probe reports it. [Install jq](https://jqlang.org/download/).
- **Biome** available to the repo, in its `node_modules` or on `PATH`. Biome is never downloaded on
  the fly; if it is not present while a Biome config governs the repo, the batch row skips the
  file. **Biome 2.x is recommended** (tested against 2.6.7): the adapter passes `--write`,
  `--linter-enabled=false`, `--error-on-warnings`, `--reporter=concise`, `--max-diagnostics=none`
  and `--no-errors-on-unmatched`, and on much older releases those flags may be absent.
- A **`biome.json`** or **`biome.jsonc`** in the repo, the opt-in.
- A SessionStart probe reports a missing `biome` once per session, from `prerequisites.json`, only
  where a `biome.json` or `biome.jsonc` sits in the project directory or above it, and a drifted
  git-hook entry. A repository whose only Biome config is nested below the project directory gets
  no probe line, though the hooks still run there. Run
  `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` to see what resolves; it is
  read-only and installs nothing.

The hook scripts run on Bash 3.2+.

### Hook budget accounting

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md),
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
`javascript_format_end_of_turn` off (its default) at 1 spawn. The Biome adapter path, one `Edit`
of a `.ts` file under a `biome.json` with the native Biome binary on `PATH`, measured 16 spawns
before and after the resolver landed (2026-11-17, WSL2 Ubuntu, bash 5.3.9).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install javascript-format@melodic-software
```

Then verify prerequisites with `/javascript-format:setup check` or
`node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`.

## Configuration

The formatting rules come from the `biome.json` already in your repository, which
the plugin reads automatically. To change the rules, edit that file.

Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `javascript_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `javascript_format_lint_gitignored` | `false` | Set `true` to rewrite a file the repository gitignores. Off by default. |
| `javascript_format_end_of_turn` | `false` | Set `true` to run the pre-commit `lint` entry over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. Nothing is rewritten. |

Set them interactively with `/plugin configure javascript-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install javascript-format@<marketplace> --config javascript_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `javascript_format_enabled` | boolean | `true` | After each batch of tool calls, run the resolved format command over the JavaScript, TypeScript and JSON files it wrote |
| `javascript_format_lint_gitignored` | boolean | `false` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `javascript_format_end_of_turn` | boolean | `false` | At the end of each turn, run the pre-commit lint entry over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Set the options above for `javascript-format@<marketplace>`, replacing `<marketplace>` with the
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
