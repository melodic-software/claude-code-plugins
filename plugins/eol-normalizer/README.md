# eol-normalizer

A Claude Code plugin that normalizes a file's working-tree line endings the
moment you edit it. On every `Write` or `Edit` it resolves the file's
`.gitattributes` `eol=` value via
[`git check-attr`](https://git-scm.com/docs/git-check-attr) and rewrites the
file's line endings to match — symmetric CRLF↔LF, idempotent, best-effort.

It uses **your repository's own `.gitattributes`** — it ships no policy and
imposes no rules of its own.

## Behavior

- **LF arm (every OS).** A file resolving to `eol=lf` is normalized CRLF→LF.
- **CRLF arm (every OS).** A file resolving to `eol=crlf` is normalized
  LF→CRLF. The hook compensates for tool writes that bypass git's checkout
  smudge, and such writes happen on any platform — an LF write to an
  `eol=crlf` path violates the repo's policy on Linux/macOS just as much as on
  Windows.
- **Binary guard.** `eol` alone is not proof of text: under a broad
  `* text=auto eol=lf` rule, the `eol` attribute resolves to `lf` for binaries
  too. The hook mirrors gitattributes semantics — explicit `text` is trusted,
  `-text` skips, and `text=auto` content-sniffs (NUL scan of the first 8000
  bytes, git's own detection window) — so binary files are never rewritten.
- **Unspecified → no-op.** A path with no `eol=` attribute is left untouched.
  There is no hardcoded extension list — resolution is entirely
  `.gitattributes`-driven, so narrow rules (a single `eol=lf` path) correctly
  win over broad ones (`*.txt eol=crlf`).
- **Advisory, never blocking.** The hook always exits `0`. Make a commit hook or
  CI (`git add --renormalize`, an EditorConfig check) your hard gate.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **git** on `PATH` — the attribute resolution (`git check-attr`) and repo-root
  detection depend on it. Without a git repository the hook is a quiet no-op
  (nothing to normalize against — not a missing prerequisite).

Rewriting uses `perl` when present, falling back to `tr`/`awk` otherwise, so no
extra tooling is required.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while normalization
still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install eol-normalizer@<marketplace>
```

Then verify prerequisites with `/eol-normalizer:setup check`.

## Configuration

The normalization policy itself is your repository's `.gitattributes`, which the
hook reads automatically — to change which files normalize to which endings,
edit your `.gitattributes`. One `userConfig` option tunes the hook's own
behavior:

| Option | Type | Default | Effect |
|--------|------|---------|--------|
| `eol_normalizer_enabled` | boolean | `true` | Toggle the eol-normalizer hook. Set to `false` for a clean no-op. |

Set it interactively with `/plugin configure eol-normalizer@<marketplace>`, or headless on
the install command:

```shell
claude plugin install eol-normalizer@<marketplace> --config eol_normalizer_enabled=false
```

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `eol_normalizer_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED` | Normalize a written file's line endings to its .gitattributes eol value |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure eol-normalizer@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install eol-normalizer@<marketplace> -s <scope> --config eol_normalizer_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "eol-normalizer@<marketplace>": {
         "options": {
           "eol_normalizer_enabled": <value>
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

## License

MIT (SPDX-License-Identifier: MIT).
