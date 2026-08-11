# typos-format

A Claude Code plugin that spell-checks the moment you edit any file. On every
`Write` or `Edit` it runs [typos](https://github.com/crate-ci/typos) and
surfaces findings back to Claude as advisory context — including remediation
guidance for allowlisting a false positive. It is **report-only by default**;
with the `typos_format_write_changes` opt-in it applies typos' safe
corrections in place and reports every correction it applied.

It ships no rules of its own and runs unconditionally, using typos' built-in
spelling dictionary. If your repository has its own typos configuration
(`typos.toml`, `_typos.toml`, `.typos.toml`, `Cargo.toml` with
`[workspace.metadata.typos]`/`[package.metadata.typos]`, or `pyproject.toml`
with `[tool.typos]`), typos discovers and honors it automatically — no
opt-in required.

## Behavior

- **Runs on every edit, zero-config or not.** typos ships a built-in spelling
  dictionary and needs no configuration to be useful, so this hook never gates
  on a consumer typos config existing. When a config IS present, typos' own
  file-anchored discovery still finds and applies it (allowlist/exclude), in
  its documented precedence order — this plugin never re-implements that walk.
- **No extension filter.** Unlike sibling formatter plugins (Ruff, Markdown),
  typos is language-agnostic — it runs on any edited file.
- **Report-only by default.** A dictionary autocorrect is a content mutation
  you never asked for, and an unconditional writer here raced sibling
  formatter hooks on the same file with no defined ordering (#1809). Out of
  the box the hook reports findings and never modifies a file.
- **Fix in place is an opt-in.** With `typos_format_write_changes` set to
  `true`, `typos --write-changes` applies every correction it has confidence
  in. Residual findings — an entry with no known correction (e.g. a
  blank-correction `extend-words` entry marking a term "disallowed"), or one
  with more than one candidate correction — surface as advisory context, never
  auto-applied.
- **Every applied rewrite is disclosed.** A correction changes the content of
  your file, so the hook reports each one it applied — the word, its
  replacement, and the line — to Claude *and* to you, capped at ten per run
  with a count of the remainder. Nothing this hook writes is silent.
- **Remediation guidance included.** Both an applied rewrite and a residual
  finding carry the fix: add the term to `extend-words` / `extend-identifiers`
  (or an `extend-ignore-re` pattern) in your typos config if it's intentional.
  This matters most on the *applied* path — the dictionary has no memory of
  your repair, so a word you correct by hand is rewritten again on the next
  edit until the allowlist entry exists.
- **Respects your excludes.** The hook passes `--force-exclude`, so a path
  your config's `[files] exclude`/`extend-exclude` excludes (generated or
  vendored code, intentional-misspelling fixtures) is left untouched even
  though the hook passes it explicitly, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.

## Known limitation (write mode only)

Claude Code runs every matching `PostToolUse` hook in parallel for one tool
call, with no hook-level locking/ordering primitive. Under the report-only
default this hook only reads, so the worst concurrent outcome is a stale
finding. Opting `typos_format_write_changes` on in a repo where a sibling
formatter hook also rewrites the same file class (e.g. `markdown-format` on
`.md`, `ruff-format` on `.py`) re-opens the race: each hook independently
reads-then-writes with no locking, so ordering is **last-writer-wins** and a
nondeterministic clobber is possible. That double opt-in is your call to
make; the residual overlap class is tracked fleet-wide in #875.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **typos** on `PATH`. Unlike Ruff or markdownlint-cli2, typos has no
  per-repo dependency-manager convention — it is a standalone Rust binary,
  installed at the machine level (cargo, Homebrew, Conda, pacman, or a
  pre-built binary). typos is never downloaded on the fly; if it is not
  present, the hook skips with a visible once-per-session notice.
  [Install typos](https://github.com/crate-ci/typos#install).

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while typo
fixing still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install typos-format@melodic-software
```

Then verify prerequisites with `/typos-format:setup check`.

## Configuration

The rules themselves are never configured here — they come from the typos
config already in your repository, which the plugin reads automatically. To
change the rules (allowlist a false positive, ignore a pattern), edit that
file.

Two `userConfig` options tune the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `typos_format_enabled` | `true` | Kill switch — set `false` for a clean no-op. |
| `typos_format_write_changes` | `false` | Set `true` to apply corrections in place (accepting last-writer-wins with any sibling formatter hook on the same file). Default is report-only: findings are reported, no file is modified. |

Set them interactively with `/plugin configure typos-format`, or headless on the
install command:

```shell
claude plugin install typos-format@melodic-software --config typos_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the plugin off for a single repository, disable it in that project's
`enabledPlugins` instead.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `typos_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED` | Spell-check on edit of any file, unconditionally (report-only unless typos_format_write_changes is on) |
| `typos_format_write_changes` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES` | Rewrite the file in place. Off by default: findings are reported without modifying the file. Turning this on accepts last-writer-wins ordering with any sibling formatter hook that rewrites the same file. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure typos-format`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install typos-format@<marketplace> --config typos_format_enabled=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "typos-format@<marketplace>": {
         "options": {
           "typos_format_enabled": <value>
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
