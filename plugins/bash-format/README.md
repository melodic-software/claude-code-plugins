# bash-format

A Claude Code plugin that lints and formats shell scripts the moment you edit
them. On every `Write` or `Edit` of a `.sh` or `.bash` file it runs
[ShellCheck](https://www.shellcheck.net/) and (opt-in)
[shfmt](https://github.com/mvdan/sh), surfacing findings back to Claude as
advisory context.

It uses **your repository's own configuration** — `.shellcheckrc` for linting
and `.editorconfig` for formatting. It ships no rules of its own.

## Behavior

- **Lint on edit (always).** ShellCheck (`warning` severity and above) runs on
  every edit. It is non-mutating; it only reports.
- **Format on edit (opt-in).** `shfmt` runs **only when an `.editorconfig`
  section names shell files** — a shell glob such as `[*.sh]`, `[*.bash]`, or
  `[*.{sh,bash}]` (including path-prefixed forms like `[**/*.sh]`), found by
  walking up from the file to the repository root. A bare `[*]` catch-all is
  **not** an opt-in: most repos only set line-ending / charset properties there,
  and treating that as a format gate would rewrite shell files to shfmt's
  built-in defaults. A repo whose `.editorconfig` only configures other
  languages (or has none) likewise leaves shell files untouched. Path-only
  sections like `[scripts/**]` are also excluded; use an explicit shell glob.
  It runs with no parser/printer flags, so your `.editorconfig` is authoritative,
  and with `--apply-ignore` so an `ignore = true` section (e.g. for generated or
  vendored scripts) is honored even on a single edited file.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Config from the consumer.** ShellCheck discovers `.shellcheckrc` by walking
  up from the file's directory; shfmt reads `.editorconfig` the same way. No
  working-directory assumptions — the tools are anchored to the edited file.
- **Scope: files inside the current project — when `CLAUDE_PROJECT_DIR` is set.**
  With `CLAUDE_PROJECT_DIR` set, the hook acts only on shell files under it
  (symlink-resolved): a `.sh`/`.bash` file written *outside* the project — e.g. to
  a temp or scratchpad directory — is silently skipped (no lint, no format, no
  notice), deliberate defense-in-depth scoping inherited from the shared hook
  library. The OS temp tree (`TMPDIR`/`TMP`/`TEMP` and the POSIX defaults) is
  outside the project even when it sits *under* `CLAUDE_PROJECT_DIR` — the shape a
  home-directory project dir takes, where Claude Code's own session scratchpad
  would otherwise prefix-match as project content. The one exception is a project
  root that itself lives under temp (a fixture checkout built with `mktemp -d`),
  whose files are project content. Membership recognizes Windows 8.3 short-name
  spellings (`KYLESE~1`) of in-project paths — a per-volume concern: only volumes
  with 8.3 generation enabled produce such paths. If `CLAUDE_PROJECT_DIR` is **unset** (e.g. some
  headless `-p` sessions), the membership check is skipped and any existing edited
  file is processed. Either way, to lint a file the hook skipped, run `shellcheck`
  on it directly.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **ShellCheck** on `PATH` for the lint pass. Absent: the lint pass skips with
  a visible once-per-session notice.
- **shfmt** on `PATH` for the format pass (and an `.editorconfig` in your repo
  to opt in). Absent while the repo opts in: the format pass skips with a
  visible once-per-session notice. Without the `.editorconfig` opt-in the
  format pass stays quiet — the repo chose not to format.

Each pass is independent: when a tool is absent its pass is skipped (visibly)
and the other still runs.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while linting and
formatting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bash-format@<marketplace>
```

Then verify prerequisites with `/bash-format:setup check`.

## Configuration

The linting and formatting rules come from the `.shellcheckrc` and
`.editorconfig` already in your repository, which the plugin reads automatically.
To change the rules, edit those files.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `bash_format_enabled` | `true` | Toggle for the bash-format hook; set `false` for a clean no-op. |

Set it interactively with `/plugin configure bash-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install bash-format@<marketplace> --config bash_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `bash_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED` | Lint and format shell scripts on edit via ShellCheck + shfmt |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure bash-format@<marketplace>`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install bash-format@<marketplace> --config bash_format_enabled=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "bash-format@<marketplace>": {
         "options": {
           "bash_format_enabled": <value>
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
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
