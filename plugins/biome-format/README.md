# biome-format

A Claude Code plugin that formats and lints JavaScript, TypeScript, JSX, and
JSON the moment you edit them. On every `Write` or `Edit` of a `.ts`, `.tsx`,
`.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.json`, or `.jsonc` file it runs
[Biome](https://biomejs.dev/)'s `check --write`, applying safe fixes,
formatting, and import sorting, then surfaces any residual findings back to
Claude as advisory context.

It uses **your repository's own `biome.json`**. It ships no rules of its own and
runs only when your repo has opted into Biome.

## Behavior

- **Spawned only for the files it formats.** The hook is registered with one `if`
  filter per extension (`.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`,
  `.json`, `.jsonc`), so a Write/Edit of any other file never starts a hook process
  for it; the extension check inside the script is unchanged.
- **Opt-in on `biome.json`.** Biome runs **only when a `biome.json` or
  `biome.jsonc` governs the edited file**, found by walking up from the file to
  the repository root. A repo without a Biome config is left untouched rather
  than rewritten to Biome's built-in defaults, so the plugin never imposes a
  style you did not choose. (The hidden `.biome.json` / `.biome.jsonc` names are
  intentionally not treated as the opt-in: Biome only loads them from 2.4
  onward, so honoring them here would risk reformatting with built-in defaults on
  an older Biome. Use a canonical `biome.json` / `biome.jsonc`.)
- **Format + lint on edit.** `biome check --write` applies safe fixes,
  formatting, and import sorting in place. Residual diagnostics are reported
  but not auto-applied. That includes errors and, because the hook passes
  `--error-on-warnings`, warnings. Unsafe fixes are never forced.
- **Respects your ignores.** Biome honors your config's `files.includes` ignore
  rules even for the single edited file. A path your config excludes (for
  generated or vendored code) is left untouched, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Config discovery from your repo.** The hook finds the governing `biome.json`
  by walking up from the edited file and runs Biome from that config's directory,
  so a single repo-root (or subtree) config governs files in subdirectories
  beneath it.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH`. Parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **Biome** available to the repo. Installed in the repo's `node_modules`
  (the hook runs `node_modules/.bin/biome`) or on `PATH`. Biome is never
  downloaded on the fly; if it is not present while a Biome config governs the
  repo, the hook skips with a visible once-per-session notice.
  **Biome 2.x is recommended** (tested against 2.5.1): the hook invokes
  `check --write --error-on-warnings --reporter=github`, and on much older
  releases those flags may be absent, in which case the run is reported as a
  tool break rather than a finding.
- A **`biome.json`** or **`biome.jsonc`** in the repo, the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting and
linting still run.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write` and `Edit` of a `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`,
`.cjs`, `.mts`, `.cts`, `.json` or `.jsonc` file (every handler in `hooks/hooks.json` carries
one of the ten `if` rows, which keep every other extension from spawning it, and the suite pins
the whole handler set to the script's own extension set), so its cost on a clean file is the
figure that counts. Measured on Linux x86_64 under bash 5.2 in a container with
`HOOK_TELEMETRY_SINK` and `CLAUDE_PROJECT_DIR` unset, twelve interleaved trials against an
interleaved `bash -c :` floor S of about 4 ms, with a kernel census from
`strace -f -e trace=clone,clone3,fork,vfork,execve` (2026-09-07, 0.6.42):

| Event | Fires | Wall | Spawn-equivalents | Kernel census |
| --- | --- | --- | --- | --- |
| PostToolUse `Write`, clean `.ts`, no `biome.json` (opt-in absent) | 1 | 31 ms | 7.9 | 11 process creations, 5 execs: two `git rev-parse` (the working-tree probe and the root resolver), `jq`, `realpath`, the hook's own `bash` |
| PostToolUse `Write`, clean `.ts`, `biome.json` present | 1 | 117 ms | 27.5 | 34 process creations, 15 execs: the row above plus the hook's `env -u BIOME_CONFIG_PATH` wrapper, the `node_modules/.bin/biome` launcher script and the `node` it runs, the `sh -c "ldd --version"` and `ldd` of that launcher's libc probe, one `biome` binary run, and the disclosure snapshot's `mktemp`, `cp`, `cmp`, `rm` |
| PostToolUse `Write`, any other extension | 0 | none | 0 | no process; the `if` rows drop the handler before a spawn |

At a 4 ms floor the spawn-equivalent column mostly measures Biome's own run time rather than
spawns, so the census column is the number that transfers to the Windows 11 Git Bash reference
host the convention calls binding; that host's figure for this plugin has not been taken. The
residual is Biome and its launcher plus the shared library's payload reader (`jq`), working-tree
probe and root resolver (`git` twice, `realpath`) and the disclosure snapshot.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install biome-format@<marketplace>
```

Then verify prerequisites with `/biome-format:setup check`.

## Configuration

The formatting rules come from the `biome.json` already in your repository, which
the plugin reads automatically. To change the rules, edit that file.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `biome_format_enabled` | `true` | Toggle for the biome-format hook; set to `false` for a clean no-op |

Set it interactively with `/plugin configure biome-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install biome-format@<marketplace> --config biome_format_enabled=false
```

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `biome_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED` | Format and lint JS/TS/JSX/JSON on edit via Biome |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure biome-format@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
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

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
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
