# ruff-format

A Claude Code plugin that rewrites Python with [Ruff](https://docs.astral.sh/ruff/) in two places:
once per batch of tool calls in a Claude Code session, and again at git pre-commit for every
author. Both run `ruff check --fix` (safe fixes only) and `ruff format`. Findings that remain are
reported by the pre-commit entry, on the lines the commit adds; they no longer reach Claude on
each edit.

It uses **your repository's own Ruff configuration**. It ships no rules of its
own and runs only when your repo has opted into Ruff.

## Behavior

- **One rewrite per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the `.py` and `.pyi` files that `Write`, `Edit` or `MultiEdit` calls in
  the batch named, and runs Ruff once over all of them. It prints nothing and exits `0`: no
  finding and no notice goes to Claude or the user. A file that `Read` named is never rewritten.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`). Its launcher skips the
    script unless the payload mentions `.py`, so a batch without Python costs one `node` process.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
- **Opt-in on a Ruff config.** Ruff runs **only when a `.ruff.toml`,
  `ruff.toml`, or `pyproject.toml` with a `[tool.ruff]` section governs the
  edited file**, found by walking up from the file to the repository root. A
  repo without a Ruff config is left untouched rather than rewritten to Ruff's
  built-in defaults, so the plugin never imposes a style you did not choose.
  **Known limitation:** a `pyproject.toml` that expresses this as a bare
  `[tool]` header with an inline table (`[tool]` + `ruff = { ... }`) is not
  recognized. Such a repo is treated as un-configured and the hook skips (fails
  safe: a missed opt-in, never a wrong edit).
  - **Pointer**: when comparing this walk with Ruff's own, fetch
    [Config file discovery](https://docs.astral.sh/ruff/configuration/#config-file-discovery)
    live.
- **Safe fixes only.** `ruff check --fix` never applies unsafe fixes, even when your config sets
  `unsafe-fixes = true`.
- **Just-added imports are protected in the session.** The batch row passes `--unfixable F401`,
  because an import often lands one edit before the code that uses it. The pre-commit entry does
  not pass it, so an unused import goes at commit.
  - **Pointer**: when working out how the flag combines with your config's `unfixable` list, fetch
    [settings: lint.unfixable](https://docs.astral.sh/ruff/settings/#lint_unfixable) live.
- **Pre-existing drift is rewritten whole.** The batch payload carries no pre-edit bytes, so a
  file that already drifted from your config is formatted in full, as the pre-commit entry would.
- **Respects your excludes.** Both pass `--force-exclude`, so a path your config excludes
  (generated or vendored code) is left untouched even though it is passed explicitly. Files under
  `.githooks/` (installed copies) and gitignored files (unless `ruff_format_lint_gitignored` is
  set) are skipped.
- **No repo side effects.** Both pass `--no-cache`, so Ruff never writes a `.ruff_cache`
  directory into your repo.

## Git pre-commit entry

The plugin ships one git-hook entry, `ruff-check` (`git-hooks/entries.json`), which rewrites. At
commit it refuses a partly staged Python file untouched, runs `ruff check --fix` and `ruff format`
over the staged `.py` and `.pyi` files, re-stages what changed, and blocks the commit only on a
finding Ruff still reports on a line the commit adds, printed as `<path>:<line>: <message>`. It
reaches every author, not only Claude, once
`/ruff-format:setup apply install-git-hooks [scope=local|shared]` registers it with the
repository's hook manager (lefthook, husky or plain git hooks). Local scope stays in this clone;
shared scope commits the copy under `.githooks/ruff-format/`. `/ruff-format:setup check` reports
drift, and the SessionStart probe prints one line when the entry is missing, stale or edited.

Ruff comes from the repo's `.venv` (`.venv/bin/ruff`, or `.venv/Scripts/ruff.exe`) or `PATH`. When
it is missing, an agent's commit fails with the install command; a person's commit gets a one-line
notice and goes through. `git -c checks.skipmissing=ruff commit ...` skips the check while ruff is
absent. The placement rules are the check-placement convention in the marketplace repository.

An opt-in Stop row (`ruff_format_end_of_turn`) runs the same check over the uncommitted changes
at the end of a turn, without rewriting, and hands findings back to Claude once per turn.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash. A missing `node` is a hook launch error, not a skip notice.
- **jq** on `PATH`. Reads the file paths from the `PostToolBatch` payload. Absent: the batch row
  does nothing, and the SessionStart probe reports it. [Install jq](https://jqlang.org/download/).
- **Ruff** available to the repo. Installed in the repo's `.venv` (the hook
  resolves `.venv/bin/ruff`, or `.venv/Scripts/ruff.exe` on Windows, walking up
  from the edited file) or on `PATH`. Ruff is never downloaded on the fly; if
  it is not present while a Ruff config governs the repo, the batch row skips the file.
  **Ruff 0.12+ is recommended** (tested against 0.17.0): earlier releases lack stabilized
  version-aware syntax errors, and on much older releases the flags the hook passes may be absent.
- A SessionStart probe reports a missing `ruff` once per session, from `prerequisites.json`, and
  a drifted git-hook entry. The probe looks on `PATH` and at `.venv/bin/ruff` under the working
  directory or up to seven of its ancestors. The batch row also resolves a `.venv` ruff by walking
  up from the edited file, and accepts `.venv/Scripts/ruff.exe` there, so a Windows host whose only
  ruff is that file gets the probe notice while edits still format. Run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`
  to see what resolves, the same places the probe looks; it is read-only and installs nothing.
- A **Ruff config** (`.ruff.toml`, `ruff.toml`, or `pyproject.toml` with
  `[tool.ruff]`) in the repo, the opt-in.

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
`.performance/ratchets.json` holds the no-Python row at 1 spawn, and the Stop row with
`ruff_format_end_of_turn` off (its default) at 1 spawn.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install ruff-format@melodic-software
```

Then verify prerequisites with `/ruff-format:setup check`.

## Configuration

The rules themselves are never configured here. They come from the Ruff config
already in your repository, which the plugin reads automatically. To change the
rules, edit that file.

Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `ruff_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `ruff_format_lint_gitignored` | `false` | Set `true` to rewrite a file the repository gitignores. Off by default. |
| `ruff_format_end_of_turn` | `false` | Set `true` to run the pre-commit check over the uncommitted changes when a turn ends; findings go back to Claude once per turn so they are fixed before it stops. Nothing is rewritten. |

Set them interactively with `/plugin configure ruff-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install ruff-format@<marketplace> --config ruff_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `ruff_format_enabled` | boolean | `true` | After each batch of tool calls, run Ruff check --fix and format over the Python files it wrote |
| `ruff_format_lint_gitignored` | boolean | `false` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or linted, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `ruff_format_end_of_turn` | boolean | `false` | At the end of each turn, run the pre-commit Ruff check over the lines changed since the last commit and hand any findings back so they are fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Set the options above for `ruff-format@<marketplace>`, replacing `<marketplace>` with the
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
