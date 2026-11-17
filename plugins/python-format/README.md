# python-format

A Claude Code plugin that formats and lints Python with whichever tools your repository uses, as two
separate concerns. Formatting runs once per batch of tool calls in a Claude Code session and again
at git pre-commit for every author; linting reports at pre-commit, on the lines the commit adds.
No lint autofix runs in either place, and no finding reaches Claude on each edit.

Each concern resolves per repository, in this order:

1. your **python record**, `.claude/ecosystems/python.yaml`: `fix-cmd` formats, `lint-cmd` lints
   (the ecosystem-commands contract in the marketplace repository). Any tool can be named there.
2. the shipped **Ruff adapter**, when a `.ruff.toml`, `ruff.toml` or `pyproject.toml` with a
   `[tool.ruff]` section governs the file: import sorting where your lint config selects it, then
   `ruff format`; `ruff check` for lint.
3. **nothing**: a repository with neither is left untouched, and `/python-format:setup check`
   reports the concern unresolved.

The plugin ships no rules and no tool choice of its own.

## Behavior

- **One format per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the `.py` and `.pyi` files that `Write`, `Edit` or `MultiEdit` calls in
  the batch named, and runs each file's resolved format command once over them. It prints nothing
  and exits `0`. A file that `Read` named is never rewritten.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`). Its launcher skips the
    script unless the payload mentions `.py`, so a batch without Python costs one `node` process.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
- **A record runs only when it is the team's.** A record committed to the repository runs when it,
  and every repository file its command names, match the default branch (`origin/HEAD`). One that
  differs, such as a record edited on a branch, runs nothing (not even the Ruff adapter) until it
  is merged or approved for your clone with `/python-format:setup apply approve-record`. Your own
  `~/.claude/ecosystems/python.yaml` and an untracked `python.local.yaml` need no approval. A
  command must hold `<files>` to run from a hook; file names reach it as arguments, never as shell
  text.
- **Ruff adapter opt-in.** The adapter walks up from the file to the repository root for a Ruff
  config. **Known limitation:** a `pyproject.toml` that uses a bare `[tool]` header with an inline
  `ruff = { ... }` table is not recognized, so the adapter skips (a missed opt-in, never a wrong
  edit).
  - **Pointer**: when comparing this walk with Ruff's own, fetch
    [Config file discovery](https://docs.astral.sh/ruff/configuration/#config-file-discovery)
    live.
- **Pre-existing drift is rewritten whole.** The batch payload carries no pre-edit bytes, so a
  file that already drifted from your config is formatted in full, as the pre-commit entry would.
- **Respects your excludes.** The adapter passes `--force-exclude` and `--no-cache`. Files under
  `.githooks/` (installed copies) and gitignored files (unless `python_format_lint_gitignored` is
  set) are skipped.

## Git pre-commit entries

The plugin ships two git-hook entries (`git-hooks/entries.json`):

- `format` rewrites. At commit it refuses a partly staged Python file untouched, runs the resolved
  format command over the staged `.py` and `.pyi` files, and re-stages what changed.
- `lint` reports. It runs the resolved lint command and blocks the commit only on a finding on a
  line the commit adds, printed as `<path>:<line>: <message>`. A linter that exits non-zero with no
  such line fails the commit and shows its output.

They reach every author, not only Claude, once
`/python-format:setup apply install-git-hooks [scope=local|shared]` registers them with the
repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this clone;
shared scope commits the copies under `.githooks/python-format/`. `/python-format:setup check`
reports drift, including a copy of the earlier single `ruff-check` entry, which that action
retires; a decline of `ruff-check` carries to both.

When the resolved tool is missing, an agent's commit fails with the install command; a person's
commit gets a one-line notice and goes through. `git -c checks.skipmissing=<tool> commit ...` skips
the entry while the tool is absent. The placement rules are the check-placement convention in the
marketplace repository.

An opt-in Stop row (`python_format_end_of_turn`) runs the `lint` entry over the uncommitted changes
at the end of a turn and hands findings back to Claude once per turn.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash. A missing `node` is a hook launch error, not a skip notice.
- **jq** on `PATH`. Reads the file paths from the `PostToolBatch` payload. Absent: the batch row
  does nothing, and the SessionStart probe reports it. [Install jq](https://jqlang.org/download/).
- **The resolved tool** available to the repo. A record's tool is whatever its command names. The
  Ruff adapter resolves Ruff from the repo's `.venv` (`.venv/bin/ruff`, or `.venv/Scripts/ruff.exe`
  on Windows, walking up from the edited file) or `PATH`, and never downloads it; when it is absent
  the batch row skips the file. **Ruff 0.12+ is recommended** for the adapter (tested against
  0.17.4).
- A SessionStart probe reports a missing `ruff` once per session, from `prerequisites.json`, only
  where a Ruff config sits in the project directory or above it, and a drifted git-hook entry. A
  record's tool is reported by `/python-format:setup check` and by the entry's missing-tool line.
  Run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` to see what resolves; it
  is read-only and installs nothing.

The hook scripts run on Bash 3.2+.

### Hook budget accounting

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch of every
session. Its launcher flag `--skip-unless-stdin-contains .py` closes before bash starts when the
payload never mentions `.py`. Measured on WSL2 Ubuntu (bash 5.3.9, ruff 0.17.0, node 24) on
2026-10-15, with the row launched as `hooks.json` registers it, ten fires per case; spawns are
from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| No `.py` in the payload | 0.031 s | 0.030-0.033 s | 1 (the `node` launcher) |
| A `Read` of a `.py` file, nothing to rewrite | 0.039 s | 0.036-0.041 s | 6 |
| One `Edit` of a `.py` file that needs a rewrite | 0.083 s | 0.073-0.107 s | 17 |

The ceiling for a per-batch formatter row is 1 s median per fire. Fences:
`.performance/ratchets.json` holds the no-Python row at 1 spawn, the record path (an approved
python record formatting one file) at 27 spawns, and the Stop row with
`python_format_end_of_turn` off (its default) at 1 spawn. The Ruff adapter path measured 20 spawns
before and after the resolver landed (2026-11-16, WSL2 Ubuntu, bash 5.3.9).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install python-format@melodic-software
```

Then verify prerequisites with `/python-format:setup check`.

## Configuration

The rules themselves are never configured here. They come from the Ruff config
already in your repository, which the plugin reads automatically. To change the
rules, edit that file.

Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `python_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `python_format_lint_gitignored` | `false` | Set `true` to rewrite a file the repository gitignores. Off by default. |
| `python_format_end_of_turn` | `false` | Set `true` to run the pre-commit check over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. Nothing is rewritten. |

Set them interactively with `/plugin configure python-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install python-format@<marketplace> --config python_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `python_format_enabled` | boolean | `true` | After each batch of tool calls, run the resolved format command over the Python files it wrote |
| `python_format_lint_gitignored` | boolean | `false` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `python_format_end_of_turn` | boolean | `false` | At the end of each turn, run the pre-commit lint entry over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Set the options above for `python-format@<marketplace>`, replacing `<marketplace>` with the
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
