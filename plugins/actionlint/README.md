# actionlint

A Claude Code plugin that lints GitHub Actions workflow files the moment you
edit them. On every `Write` or `Edit` of a file under `.github/workflows/`
(`*.yml` or `*.yaml`) it runs [actionlint](https://github.com/rhysd/actionlint)
and surfaces any findings back to Claude as advisory context.

It ships no rules of its own and no binary. It runs the `actionlint` already on
your `PATH`.

## Behavior

- **Lint on edit.** actionlint runs on every edit of a workflow file. It is
  non-mutating; it only reports.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Scoped to workflows.** Only files matching `.github/workflows/*.yml` and
  `.github/workflows/*.yaml` are linted. Other YAML is left alone. The registration
  carries the matching `if` filters (`Edit(**/.github/workflows/*.yml)` and the
  `.yaml` twin), so a Write/Edit of any other file never starts a hook process for it.
- **External run-block linters disabled (`-shellcheck= -pyflakes=`).**
  actionlint's embedded-bash ShellCheck and `shell: python` pyflakes
  integrations are turned off. Each spawns a subprocess per `run:` block.
  ShellCheck deadlocks on large blocks under the Windows subprocess IPC path in
  actionlint 1.7.x, and either adds latency unsuited to an edit-time hook.
  Native workflow diagnostics are unaffected; run the full integrations in CI.
- **Graceful degrade.** When `actionlint` (or `jq`) is not on `PATH` the hook
  skips and says so, a once-per-session notice to both Claude
  (`additionalContext`) and you (`systemMessage`), never a silent no-op.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH`. Parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **actionlint** on `PATH`. The linter itself. Absent: workflow lint skips
  with a visible once-per-session notice. See the
  [actionlint install guide](https://github.com/rhysd/actionlint/blob/main/docs/install.md).

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write` and `Edit` of a `.yml` or `.yaml` file under
`.github/workflows/` (every handler in `hooks/hooks.json` carries one of the two `if` rows,
which keep every other file from spawning it, and the suite pins the whole handler set to the
script's own workflow filter), so its cost on a clean workflow is the figure that counts.
Measured on Linux x86_64 under bash 5.2 in a container with `HOOK_TELEMETRY_SINK` and
`CLAUDE_PROJECT_DIR` unset, twelve interleaved trials against an interleaved `bash -c :` floor
S of about 4 ms, with a kernel census from `strace -f -e trace=clone,clone3,fork,vfork,execve`
(2026-09-07, 0.8.43):

| Event | Fires | Wall | Spawn-equivalents | Kernel census |
| --- | --- | --- | --- | --- |
| PostToolUse `Write`, clean `.github/workflows/*.yml` | 1 | 34 ms | 7.9 | 14 process creations (one trial in nine reached 15; actionlint's own threads vary), 5 execs: `actionlint`, `git`, two `jq`, the hook's own `bash` |
| PostToolUse `Write`, any other file | 0 | none | 0 | no process; the `if` rows drop the handler before a spawn |

At a 4 ms floor the spawn-equivalent column mostly measures actionlint's own run time rather
than spawns, so the census column is the number that transfers to the Windows 11 Git Bash
reference host the convention calls binding; that host's figure for this plugin has not been
taken. The residual is actionlint itself plus the payload parse (`jq`) and the root resolver
(`git`).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install actionlint@<marketplace>
```

Then verify prerequisites with `/actionlint:setup check`.

## Configuration

actionlint auto-discovers its own `.github/actionlint.yaml` config from your
repository when present. Two `userConfig` options tune the hook itself:

- **`actionlint_enabled`** (boolean, default `true`). Kill switch for the
  actionlint-check hook.
- **`stdin_read_timeout`** (number, default `2`, minimum `1`). **Idle** bound in
  seconds on reading the hook payload from stdin. Any byte arriving resets it, so
  a large or slowly-delivered payload is never cut off while it is still coming;
  it fires only once the pipe has gone silent for that long, and this hook then
  fails open (skips). On a shell whose `read -t` accepts fractional values the
  bound is read in four slices, so the stall is detected within a quarter of the
  configured interval; where fractional timeouts are unavailable (Bash 3.2,
  the macOS system shell) the bound is read as one window and a producer that sends
  bytes then goes silent can take up to two intervals. A producer that keeps
  emitting is bounded by Claude Code's own hook timeout, not by this value. If
  this shell's `read -t` will not accept the setting, or the setting is `0`, the
  hook falls back to the default.

Configure interactively with `/plugin configure actionlint@<marketplace>` or headless at
install time:

```shell
claude plugin install actionlint@<marketplace> --config actionlint_enabled=false
```

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `actionlint_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED` | Lint GitHub Actions workflow files on edit via actionlint |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin — how long the pipe may go silent before the hook gives up and fails open |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure actionlint@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
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

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
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
