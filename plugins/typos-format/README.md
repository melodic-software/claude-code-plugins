# typos-format

A Claude Code plugin that fixes spelling typos the moment you edit any file.
On every `Write` or `Edit` it runs [typos](https://github.com/crate-ci/typos)'s
`--write-changes`, reports every correction it applied, and surfaces any
residual (unfixable) findings back to Claude as advisory context — including
remediation guidance for allowlisting a false positive.

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
- **Fix in place.** `typos --write-changes` applies every correction it has
  confidence in. Residual findings — an entry with no known correction (e.g.
  a blank-correction `extend-words` entry marking a term "disallowed"), or one
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
- **Report-only mode available.** Set `typos_format_write_changes` to `false`
  and the hook reports what typos found without ever modifying a file.
- **Respects your excludes.** The hook passes `--force-exclude`, so a path
  your config's `[files] exclude`/`extend-exclude` excludes (generated or
  vendored code, intentional-misspelling fixtures) is left untouched even
  though the hook passes it explicitly, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.

## Known limitation

Claude Code runs every matching `PostToolUse` hook in parallel for one tool
call. This hook has no extension filter, so on a repo with both a typos
config and another formatter's config (e.g. Ruff), editing a matching file
fires both hooks concurrently — each independently reading-then-writing the
same file with no locking, so a nondeterministic clobber is possible. This
risk pre-exists this plugin (it already applies between `eol-normalizer` and
every formatter hook) and is not addressed here; no hook-level
locking/ordering primitive exists in Claude Code today.

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
| `typos_format_write_changes` | `true` | Set `false` for report-only: findings are reported, no file is modified. |

Set them interactively with `/plugin configure typos-format`, or headless on the
install command:

```shell
claude plugin install typos-format@melodic-software --config typos_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the plugin off for a single repository, disable it in that project's
`enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
