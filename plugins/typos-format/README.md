# typos-format

A Claude Code plugin that fixes spelling typos the moment you edit any file.
On every `Write` or `Edit` it runs [typos](https://github.com/crate-ci/typos)'s
`--write-changes`, then surfaces any residual (unfixable) findings back to
Claude as advisory context — including remediation guidance for allowlisting
a false positive.

It uses **your repository's own typos configuration**. It ships no rules of
its own and runs only when your repo has opted into typos.

## Behavior

- **Opt-in on a typos config.** typos runs **only when a `typos.toml`,
  `_typos.toml`, `.typos.toml`, `Cargo.toml` (with
  `[workspace.metadata.typos]`/`[package.metadata.typos]`), or `pyproject.toml`
  with a `[tool.typos]` section governs the edited file**, found by walking up
  from the file to the repository root, in that precedence order — the same
  discovery typos itself uses. A repo without a typos config is left untouched
  rather than checked against typos' built-in dictionary, so the plugin never
  imposes a check you did not choose.
- **No extension filter.** Unlike sibling formatter plugins (Ruff, Markdown),
  typos is language-agnostic — it runs on any edited file, gated only by the
  config opt-in above.
- **Fix in place.** `typos --write-changes` applies every correction it has
  confidence in. Residual findings — an entry with no known correction (e.g.
  a blank-correction `extend-words` entry marking a term "disallowed") —
  surface as advisory context, never auto-applied.
- **Remediation guidance included.** Every residual finding's advisory text
  points at the fix: add the term to `extend-words` / `extend-identifiers`
  (or an `extend-ignore-re` pattern) in your typos config if it's intentional.
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
  present while a typos config governs the repo, the hook skips with a
  visible once-per-session notice. [Install typos](https://github.com/crate-ci/typos#install).
- A **typos config** (`typos.toml`, `_typos.toml`, `.typos.toml`, or an
  equivalent `Cargo.toml`/`pyproject.toml` section) in the repo — the opt-in.

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

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `typos_format_enabled` | `true` | Kill switch — set `false` for a clean no-op. |

Set it interactively with `/plugin configure typos-format`, or headless on the
install command:

```shell
claude plugin install typos-format@melodic-software --config typos_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the plugin off for a single repository, disable it in that project's
`enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
