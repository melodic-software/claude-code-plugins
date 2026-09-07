# ruff-format

A Claude Code plugin that formats and lints Python the moment you edit it. On
every `Write` or `Edit` of a `.py` or `.pyi` file it runs
[Ruff](https://docs.astral.sh/ruff/)'s `check --fix` (safe fixes only) and
`format`, then surfaces any residual findings back to Claude as advisory
context.

It uses **your repository's own Ruff configuration**. It ships no rules of its
own and runs only when your repo has opted into Ruff.

## Behavior

- **Spawned only for Python files.** The hook is registered with the `if` filters
  `Edit(*.py)` and `Edit(*.pyi)`, so a Write/Edit of any other file never starts a
  hook process for it; the extension check inside the script is unchanged.
- **Opt-in on a Ruff config.** Ruff runs **only when a `.ruff.toml`,
  `ruff.toml`, or `pyproject.toml` with a `[tool.ruff]` section governs the
  edited file**, found by walking up from the file to the repository root, the
  same discovery Ruff itself uses (a `pyproject.toml` without `[tool.ruff]` is
  ignored, exactly as Ruff ignores it). A repo without a Ruff config is left
  untouched rather than rewritten to Ruff's built-in defaults, so the plugin
  never imposes a style you did not choose. **Known limitation:** a
  `pyproject.toml` that expresses this as a bare `[tool]` header with an inline
  table (`[tool]` + `ruff = { ... }`) is not recognized, even though Ruff
  itself honors that form. Such a repo is treated as un-configured and the
  hook skips (fails safe: a missed opt-in, never a wrong edit).
- **Fix + format on edit.** `ruff check --fix` applies safe fixes (never
  `--unsafe-fixes`) and `ruff format` formats in place. Residual diagnostics
  are reported but not auto-applied.
- **Just-added imports are protected.** The hook passes `--unfixable F401`, so
  an unused import is *reported* but never auto-deleted. During iterative
  editing an import often lands one edit before the code that uses it. This
  extends your config's own `unfixable` list; it does not replace it.
- **Syntax errors are version-aware.** Ruff's parser checks syntax against your
  configured `target-version` (or the `requires-python` floor it infers), so
  code using syntax newer than your Python floor surfaces as a finding.
- **Respects your excludes.** The hook passes `--force-exclude`, so a path your
  config excludes (generated or vendored code) is left untouched even though
  the hook passes it explicitly, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.
- **No repo side effects.** The hook passes `--no-cache`, so Ruff never writes
  a `.ruff_cache` directory into your repo on edits.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH`. Parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **Ruff** available to the repo. Installed in the repo's `.venv` (the hook
  resolves `.venv/bin/ruff`, or `.venv/Scripts/ruff.exe` on Windows, walking up
  from the edited file) or on `PATH`. Ruff is never downloaded on the fly; if
  it is not present while a Ruff config governs the repo, the hook skips with a
  visible once-per-session notice. **Ruff 0.12+ is recommended**
  (tested against 0.15.20): earlier releases lack stabilized version-aware
  syntax errors, and on much older releases the flags the hook passes may be
  absent, in which case the run is reported as a tool break rather than a
  finding.
- A **Ruff config** (`.ruff.toml`, `ruff.toml`, or `pyproject.toml` with
  `[tool.ruff]`) in the repo, the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting
and linting still run.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write` and `Edit` of a `.py` or `.pyi` file (the two `if`
rows in `hooks/hooks.json` keep every other extension from spawning it, and the suite pins
those rows to the script's own extension set), so its cost on a clean Python file is the figure
that counts. Measured on Linux x86_64 under bash 5.2 in a container, twelve interleaved trials
against an interleaved `bash -c :` floor S of about 2 ms, with a kernel census from
`strace -f -e trace=clone,clone3,fork,vfork,execve` (2026-09-07, 0.6.43):

| Event | Fires | Wall | Spawn-equivalents | Kernel census |
| --- | --- | --- | --- | --- |
| PostToolUse `Write`, clean `.py`, no Ruff config (opt-in absent) | 1 | 32 ms | 13.2 | 10 process creations, 4 execs: `git`, `jq`, `realpath`, the hook's own `bash` |
| PostToolUse `Write`, clean `.py`, `ruff.toml` present | 1 | 79 ms | 35.4 | 44 process creations, 17 execs: the row above plus six `ruff` runs through the `.venv/bin/ruff` launcher and the disclosure snapshot's `mktemp`, `cp`, `cmp`, `rm` |
| PostToolUse `Write`, any other extension | 0 | none | 0 | no process; the `if` rows drop the handler before a spawn |

At a 2 ms floor the spawn-equivalent column mostly measures Ruff's own run time rather than
spawns, so the census column is the number that transfers to the Windows 11 Git Bash reference
host the convention calls binding; that host's figure for this plugin has not been taken. The
residual is Ruff itself plus the shared library's payload reader (`jq`), root resolver (`git`,
`realpath`) and the disclosure snapshot.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install ruff-format@<marketplace>
```

Then verify prerequisites with `/ruff-format:setup check`.

## Configuration

The rules themselves are never configured here. They come from the Ruff config
already in your repository, which the plugin reads automatically. To change the
rules, edit that file.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `ruff_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |

Set it interactively with `/plugin configure ruff-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install ruff-format@<marketplace> --config ruff_format_enabled=false
```

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `ruff_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED` | Run Ruff check --fix and format on edit of a Python file |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure ruff-format@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install ruff-format@<marketplace> -s <scope> --config ruff_format_enabled=<value>
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

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "ruff-format@<marketplace>": {
         "options": {
           "ruff_format_enabled": <value>
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
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
