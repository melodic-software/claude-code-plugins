# eol-normalizer

A Claude Code plugin that normalizes the working-tree line endings of the files
Claude writes. Once per batch of tool calls, for each file a `Write`, `Edit` or
`MultiEdit` in the batch named, it resolves the file's `.gitattributes` `eol=`
value via [`git check-attr`](https://git-scm.com/docs/git-check-attr) and
rewrites the file's line endings to match. Symmetric CRLF↔LF, idempotent,
best-effort, and silent: nothing it does reaches the model.

It uses **your repository's own `.gitattributes`**. It ships no policy and
imposes no rules of its own.

## Behavior

- **LF arm (every OS).** A file resolving to `eol=lf` is normalized CRLF→LF.
- **CRLF arm (every OS).** A file resolving to `eol=crlf` is normalized
  LF→CRLF. The hook compensates for tool writes that bypass git's checkout
  smudge, and such writes happen on any platform. An LF write to an
  `eol=crlf` path violates the repo's policy on Linux/macOS just as much as on
  Windows.
- **Binary guard.** `eol` alone is not proof of text: under a broad
  `* text=auto eol=lf` rule, the `eol` attribute resolves to `lf` for binaries
  too. The hook mirrors gitattributes semantics. Explicit `text` is trusted,
  `-text` skips, and `text=auto` content-sniffs (NUL scan of the first 8000
  bytes, git's own detection window), so binary files are never rewritten.
- **Unspecified is a no-op.** A path with no `eol=` attribute is left untouched.
  There is no hardcoded extension list. Resolution is entirely
  `.gitattributes`-driven, so narrow rules (a single `eol=lf` path) correctly
  win over broad ones (`*.txt eol=crlf`).
- **Gitignored is a no-op.** A file the repository gitignores and does not track is
  left alone, since a rewrite of an ignored file has no git checkout to undo it.
  A tracked file matching an ignore pattern stays in scope. Any failure to decide
  (git absent, no repo, `check-ignore` error) acts as before. Set
  `eol_normalizer_lint_gitignored=true` to act on ignored files (see the Options
  reference).
- **Reads are never rewritten.** A file that only a `Read` or a shell command
  named is left alone, and a file under `.githooks/` (an installed copy) is skipped.
- **Advisory, never blocking, silent.** The hook always exits `0` and prints
  nothing. It has no pre-commit entry because `git add` applies the same
  `.gitattributes` to the bytes it stores: a CRLF file under `eol=lf` and an LF
  file under `eol=crlf` are both committed as LF, whether or not this hook ran
  (`hooks/eol-git-add.test.sh` pins it). The working tree is what this hook
  fixes: a CRLF shell script fails to run before it is ever staged. For a repository
  whose files were committed with the wrong endings, `git add --renormalize` and
  an EditorConfig check in CI remain the gates.

## Requirements

- **Node.js** on `PATH`. Every hook row runs through `node hooks/exec-bash.mjs`, which then
  starts Bash. We do not assume a Claude Code install brings Node, so without `node` the
  hook does not launch and nothing is normalized. Pointer: when deciding whether an install
  brings Node, fetch [setup: Install with npm](https://code.claude.com/docs/en/setup#install-with-npm)
  live. As of: 2026-10-11. Recheck trigger: that section or [System requirements](https://code.claude.com/docs/en/setup#system-requirements) changes which
  install needs Node at runtime. [Install Node.js](https://nodejs.org/en/download).
- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH`. Parses the hook payload. Absent: the hook exits silently and
  normalizes nothing; `/eol-normalizer:check` reports it. [Install jq](https://jqlang.org/download/).
- **git** on `PATH`. The attribute resolution (`git check-attr`) and repo-root
  detection depend on it. Without a git repository the hook is a quiet no-op
  (nothing to normalize against, not a missing prerequisite).

Rewriting uses `perl` when present, falling back to `tr`/`awk` otherwise, so no
extra tooling is required.

The hook itself runs on Bash 3.2+.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch of every
session. Its launcher flag `--skip-unless-stdin-contains file_path` closes before bash starts when no
tool call in the batch names a file path. The flag takes one text and the row must cover `Write`,
`Edit` and `MultiEdit`, so `file_path` is the narrowest text that covers all three; the script then
returns at once, before it starts `jq` or `git`, unless the batch holds one of them. The row has no
`if` and no extension filter, and that is deliberate (#3411): which files it normalizes is decided by
the consuming repository's `.gitattributes` through `git check-attr eol text`, not by file type, so
the set a filter would have to reproduce is every file. Measured on WSL2 Ubuntu (bash 5.3.9, node 24,
jq 1.8.2) on 2026-10-15, with the row launched as `hooks.json` registers it, ten fires per case,
repository `.gitattributes` saying `eol=lf`; spawns are from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| A `Bash` call only (no file path) | 0.047 s | 0.044-0.054 s | 1 (the `node` launcher) |
| A `Read` of a governed file | 0.051 s | 0.045-0.058 s | 3 |
| One `Edit` of a CRLF file that needs a rewrite | 0.078 s | 0.068-0.094 s | 16 |

The ceiling for a per-batch formatter row is 1 s median per fire. Fences:
`.performance/ratchets.json` holds the no-file-path batch at 1 spawn and the Read-only batch at 3.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install eol-normalizer@<marketplace>
```

Then verify prerequisites with `/eol-normalizer:setup check`. `/eol-normalizer:check` reports whether `node` and `jq` resolve.

## Configuration

The normalization policy itself is your repository's `.gitattributes`, which the
hook reads automatically. To change which files normalize to which endings,
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

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `eol_normalizer_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED` | Normalize a written file's line endings to its .gitattributes eol value |
| `eol_normalizer_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_LINT_GITIGNORED` | By default the hook leaves a file the repository gitignores alone: it is not normalized, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure eol-normalizer@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install eol-normalizer@<marketplace> -s <scope> --config eol_normalizer_enabled=<value>
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
       "eol-normalizer@<marketplace>": {
         "options": {
           "eol_normalizer_enabled": <value>
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
