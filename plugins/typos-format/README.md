# typos-format

A Claude Code plugin that spell-checks the moment you edit any file. On every
`Write`, `Edit`, or `NotebookEdit` it runs [typos](https://github.com/crate-ci/typos) and
surfaces findings back to Claude as advisory context, including remediation
guidance for allowlisting a false positive. It is **report-only by default**;
with the `typos_format_write_changes` opt-in it applies typos' safe
corrections in place and reports every correction it applied.

It ships one fleet-wide protection of its own: a bundled
`config/default-typos.toml` injected via `typos -c` so write mode cannot
silently corrupt git SHAs. Otherwise it runs unconditionally on typos'
built-in spelling dictionary. If your repository has its own typos
configuration (`typos.toml`, `_typos.toml`, `.typos.toml`, `Cargo.toml` with
`[workspace.metadata.typos]`/`[package.metadata.typos]`, or `pyproject.toml`
with `[tool.typos]`), typos discovers it from the target path and merges
`extend-*` keys with the bundled file rather than replacing them. No
opt-in required.

## Behavior

- **Runs on every edit, zero-config or not.** typos ships a built-in spelling
  dictionary and needs no configuration to be useful, so this hook never gates
  on a consumer typos config existing. When a config IS present, typos' own
  file-anchored discovery still finds and applies it (allowlist/exclude), in
  its documented precedence order. This plugin never re-implements that walk.
- **Scan is language-agnostic; write is extension-scoped.** The read-only scan
  runs on any edited file (unlike sibling formatter plugins). Opt-in write mode
  only calls `--write-changes` for an explicit allowlist of source, prose, and
  hand-edited config extensions. Unknown extensions, extensionless paths, and
  fixture/lock/binary-adjacent types stay report-only even when
  `typos_format_write_changes` is on (#2650).
- **Report-only by default.** A dictionary autocorrect is a content mutation
  you never asked for, and an unconditional writer here raced sibling
  formatter hooks on the same file with no defined ordering (#1809). Out of
  the box the hook reports findings and never modifies a file.
- **Fix in place is an opt-in, then an allowlist.** With
  `typos_format_write_changes` set to `true`, `typos --write-changes` applies
  every correction it has confidence in, but only when the edited path's
  extension is on the write allowlist. Residual findings surface as advisory
  context, never auto-applied: an entry with no known correction (e.g. a
  blank-correction `extend-words` entry marking a term "disallowed"), or one
  with more than one candidate correction.
- **Every applied rewrite is disclosed.** A correction changes the content of
  your file, so the hook reports each one it applied (the word, its
  replacement, and the line) to Claude *and* to you, capped at ten per run
  with a count of the remainder. Nothing this hook writes is silent.
- **Remediation guidance included.** Both an applied rewrite and a residual
  finding carry the fix: add the term to `extend-words` / `extend-identifiers`
  (or an `extend-ignore-re` pattern) in your typos config if it's intentional.
  This matters most on the *applied* path. The dictionary has no memory of
  your repair, so a word you correct by hand is rewritten again on the next
  edit until the allowlist entry exists.
- **Respects your excludes.** The hook passes `--force-exclude`, so a path
  your config's `[files] exclude`/`extend-exclude` excludes (generated or
  vendored code, intentional-misspelling fixtures) is left untouched even
  though the hook passes it explicitly, with no advisory noise.
- **Gitignored paths are out of scope.** A file the repository gitignores is
  neither reported nor rewritten, matching hook-precision rule 6. Set
  `typos_format_lint_gitignored` to `true` to act on gitignored files too. A
  tracked file that matches an ignore pattern stays in scope. typos' own
  `[files] extend-exclude` still applies downstream when the hook does run.
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

**Timeout tail.** The handler sets `"timeout": 15`, well under the 600-second
default for a command hook, and Claude Code discards the output of a hook it
cancels at its timeout ([hooks reference](https://code.claude.com/docs/en/hooks),
"Timeouts", checked 2026-09-27). In write mode the second typos pass rewrites
the file before the hook classifies what changed and discloses it, so a cancel
between the two leaves your file rewritten with no disclosure. The one measured
case that crossed 15 s, 10,000 residual findings at about 15.7 s, was fixed by
moving classification to a hash lookup (about 0.6 s); no current case has
reproduced the window. Report-only mode never writes, so it has no such tail.

## Write paths the hook does not see

The matcher is `Write|Edit|NotebookEdit`, so only those tools reach it. A file
written through the `Bash` tool (a heredoc, a redirect, `sed -i`), through
`PowerShell`, or through an MCP filesystem server's write tool is never
spell-checked. `guardrails`' `block-hook-bypass`, when installed, blocks the
common Bash redirect and heredoc forms, `python3 -c` writes that use a
file-write call it recognizes, and the PowerShell write cmdlets; `sed -i`,
`perl -i`, `tee`, a standalone `cp`, and other interpreters' one-liners such as
`node -e` are outside what it detects, and it does not see MCP tools. CI is
the only gate that sees every path. The matcher does not list `MultiEdit`: the
[tools reference](https://code.claude.com/docs/en/tools-reference) does not
list it among the built-in tools, and
[permissions](https://code.claude.com/docs/en/permissions) calls it "the legacy
`MultiEdit` tool" (both checked 2026-09-27; recheck if `MultiEdit` returns to
the tools reference).

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH`. Parses the hook payload. Absent: the hook skips with a
  visible notice, once per session and agent, renewed every eighth skip. [Install jq](https://jqlang.org/download/).
- **typos** on `PATH`. Unlike Ruff or markdownlint-cli2, typos has no
  per-repo dependency-manager convention. It is a standalone Rust binary,
  installed at the machine level (cargo, Homebrew, Conda, pacman, or a
  pre-built binary). typos is never downloaded on the fly; if it is not
  present, the hook skips with a visible notice, once per session (all agents share the latch),
  renewed every eighth skip with the install route kept.
  [Install typos](https://github.com/crate-ci/typos#install).

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while typo
fixing still runs.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write`, `Edit` and `NotebookEdit`, so its cost on the path
where `typos` finds nothing is the figure that counts. Each row is interleaved trials against an
interleaved `bash -c :` floor on Windows 11 under Git Bash:

| Event | Fires | Spawn-equivalents | Measured | What changed |
| --- | --- | --- | --- | --- |
| PostToolUse `Write`, clean `.md` | 1 | 36.3 before, 26.0 after (0.6.35) | 2026-09-02, n=12 | three of sixteen processes gone: two `dirname` calls became parameter expansions and the `notebook_path` copy runs only for a payload that carries one |
| PostToolUse `Write`, clean `.md` | 1 | 18.7 (0.6.55) | 2026-09-19, n=8, plugin-quality audit | the builtin field parser in the vendored `hook-utils.sh` answers where jq ran |

The 18.7 row is the current figure for this host class. Releases after 0.6.55 have not been
measured on Windows; see [Hook cost accounting](#hook-cost-accounting) for a same-method Linux
comparison through 0.6.62.

The residual is the shared library's payload reader and telemetry emitter, cut in 0.6.36 by the
vendored `hook-utils.sh` (one batched `realpath`, no jq on the envelope), and the `typos` binary
itself.

`hooks/hooks.json` carries no `if` row, and that is deliberate (#3411). The sibling formatters
filter by extension at the manifest so a Write of any other file spawns nothing, but the
read-only scan here is language-agnostic: the set a declarative file-type filter would have to
reproduce is every file, and a narrower row would silently stop scanning whatever it left out.
The write-mode allowlist is a separate, later decision inside the script and never gates the
scan, and `NotebookEdit` stays in the matcher for the same reason. The kernel census
(`strace -f -e trace=clone,clone3,fork,vfork,execve`, Linux x86_64, `HOOK_TELEMETRY_SINK` and
`CLAUDE_PROJECT_DIR` unset, 2026-09-07, 0.6.48) on a clean `.md` `Write` is 13 process
creations and 6 execs (`typos`, `git` twice for the working-tree probe and the root resolver,
`jq`, `realpath`, the hook's own `bash`).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install typos-format@<marketplace>
```

Then verify prerequisites with `/typos-format:setup check`.

## Configuration

The rules themselves are never configured here. They come from the typos
config already in your repository, which the plugin reads automatically. To
change the rules (allowlist a false positive, ignore a pattern), edit that
file.

Three `userConfig` options tune the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `typos_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `typos_format_write_changes` | `false` | Set `true` to apply corrections in place for write-allowlisted extensions (accepting last-writer-wins with any sibling formatter hook on the same file). Default is report-only: findings are reported, no file is modified. Denied extensions stay report-only even when this is on. |
| `typos_format_lint_gitignored` | `false` | Set `true` to report (and, in write mode, rewrite) a file the repository gitignores. Off by default. |

Set them interactively with `/plugin configure typos-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install typos-format@<marketplace> --config typos_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `typos_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED` | Spell-check on edit of any file, unconditionally (report-only unless typos_format_write_changes is on) |
| `typos_format_write_changes` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES` | Rewrite the file in place for write-allowlisted extensions. Off by default: findings are reported without modifying the file. Turning this on accepts last-writer-wins ordering with any sibling formatter hook that rewrites the same file. Unknown extensions stay report-only. |
| `typos_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_LINT_GITIGNORED` | By default the hook leaves a file the repository gitignores alone: it is not rewritten or reported, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure typos-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install typos-format@<marketplace> -s <scope> --config typos_format_enabled=<value>
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
       "typos-format@<marketplace>": {
         "options": {
           "typos_format_enabled": <value>
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

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Hook cost accounting

This plugin's PostToolUse hook matches every `Write`, `Edit` and `NotebookEdit`,
so its cost is paid on every file the agent touches and it owes the
marketplace's [hook budget](../../docs/conventions/hook-budget/README.md) an
honest figure.

**Method.** `EPOCHREALTIME` wall-clock around a direct hook invocation, 12
interleaved trials, each preceded by a `bash -c :` spawn-floor run so the
reported ratio absorbs machine load. The payload is a `PostToolUse` `Write`
naming a clean scratch file inside a repository, so `typos` finds nothing and
the hook takes the path that runs on nearly every edit. Windows 11 + Git Bash,
2026-09-02.

**Counting.** Both process columns come from a `bash -x` trace of that same
invocation. An exec is a command in command position whose word resolves to a
file rather than a builtin, function, alias or keyword. A fork is an increase in
the trace's subshell-nesting depth, one per command substitution or subshell; it
undercounts, because pipeline elements fork without changing the depth. Forks
are reported beside execs because they are not free on this host: a command
substitution measures about half the cost of a spawn, so twenty-nine of them are
a large share of the run rather than a rounding error.

**Host condition.** The measuring host's `bash -c :` floor was **82 ms** for the
before run and **77 ms** for the after run, against the convention's reference
host of **≈ 80 ms**. Absolute milliseconds from a loaded host are not
comparable; the spawn-equivalent ratio is the figure that holds.

| Benign `Write`, n=12 interleaved | spawn-equivalents | @ 80 ms reference host | exec'd processes | forks |
| --- | --- | --- | --- | --- |
| Before (0.6.33) | 36.3 | ≈ 2,904 ms | 16 | 31 |
| After (0.6.35) | 26.0 | ≈ 2,080 ms | 13 | 29 |

**On 0.6.35 a clean edit cost ≈ 26.0 spawn-equivalents, ≈ 2,080 ms of
reference-host work, down 28 percent.** Two `dirname` calls became parameter
expansions, and the jq that copies `notebook_path` onto `file_path` now runs only
for a payload that carries one, which no `Write` or `Edit` does.

**Later figures.** A plugin-quality audit on 2026-09-19 measured **18.7** on
0.6.55 with the same method on the Windows host (n=8). On 2026-09-27 the same
method ran on Linux x86_64 (bash 5.2, git 2.43, jq 1.7, typos 1.42.1), with 24
trials interleaved across three releases in each round:

| Release | Median spawn-equivalents (Linux) | p25 to p75 |
| --- | --- | --- |
| 0.6.35 | 35.7 | 31.9 to 37.3 |
| 0.6.55 | 31.2 | 28.6 to 32.5 |
| 0.6.62 | 25.0 | 24.1 to 26.0 |

The Linux floor is about 1 ms, so its ratios are noisier than the Windows
host's and do not compare to its rows. What carries over is the relative
change: 0.6.62 runs about 30 percent below 0.6.35 on the same host.

**Residual, and why it stays.** The dominant single cost is the `typos` binary's
own startup, which is the point of the hook. On the measuring host it resolves
through a WinGet Links shim, an indirection this hook cannot remove. Of the
remaining twelve processes, eight to ten belong to the shared
`hooks/hook-utils.sh`: payload validation, the `file_path` read and its
project-membership scoping, and the repository-root lookup. That file is a
registered byte-identical cross-plugin cluster, so changing it is a nine-plugin
change and not this plugin's to make. Two `cygpath` calls resolve the
repository-relative argument `typos` runs on, which the tool needs to apply the
repository's own exclude rules.

**No extension gate is possible here, and that is deliberate.** `typos` is
language-agnostic, so the scan has no allowlist to short-circuit on: gating it
by the write-mode allowlist would stop reporting typos in `Dockerfile`,
`Makefile`, `.gitignore` and every extensionless file. That is a behavior
change, not a saving.

**A disabled hook costs one shell.** The `hooks/hooks.json` row reads
`typos_format_enabled` itself and exits before the script starts, so the harness's
shell is the only process a disabled hook creates. Measured in two runs on a Windows
Git Bash host under different load, 15 interleaved trials each with the switch off, the old row cost 2.5 to 4.0
times the `bash -c :` floor and the new row about 1.0 times it (medians: 96.1 ms
against 23.7 ms on a 24.0 ms floor, and 157.6 ms against 62.4 ms on a 61.9 ms floor).
With the switch on the row `exec`s the script in place of its own shell, so the
process count is unchanged.

### Why the row stays synchronous (#4677)

The row does not set `async: true`, and it is not split into an async report-only row and a
synchronous write-mode row. Running the report-only scan in the background would take it off the
per-edit critical path, but it gives up more than it saves:

- **The finding would arrive late.** A synchronous `PostToolUse` hook's `additionalContext` reaches
  Claude alongside the tool result, while Claude is still on the file. An async hook's output
  arrives on the next conversation turn, and in an idle session it waits for your next message. The
  last edit of a task is exactly the one whose finding would land after Claude reports the task
  done.
- **Headless runs would lose findings.** Under `claude -p`, Claude Code kills an async hook that is
  still running at teardown and records it as `cancelled`, so the final edits of a scripted or
  cloud run would go unchecked.
- **The 15-second budget would go away.** Claude Code does not enforce `timeout` on an async hook,
  and every firing starts its own background process with no deduplication. This hook's
  classifier is sized against that budget.
- **The missing-`typos` notice would go quiet.** Report-only findings already travel on
  `additionalContext` alone; this hook sets `systemMessage` only for a rewrite it applied (write
  mode) and for the notice (once per session, shared by all agents, renewed every eighth skip with the install route kept) that `typos` is not on `PATH`. An async hook's
  `systemMessage` is not shown to you, so that notice would reach only Claude, once, and the skip
  would be invisible to the person who can install the binary.

The synchronous cost this keeps is 472 to 649 ms per edit on a Windows Git Bash host (2026-09-23,
recorded in #4677), and 27 ms for a clean file and 35 ms with a finding on Linux
x86_64 (typos-cli 1.50.3, 20 runs each, 2026-09-28). Write mode stays synchronous on its own
grounds: a background rewrite could race the next `Edit` of the same file, the reason async was
declined for `eol-normalizer` in #4417.

- **Decision**: keep the one synchronous row in both modes.
- **Basis**: [hooks reference](https://code.claude.com/docs/en/hooks), "Run hooks in the
  background": "After the background process exits, Claude Code delivers the `additionalContext`
  and `systemMessage` fields from the hook's JSON response to Claude on the next conversation turn.
  Unlike a synchronous hook's `systemMessage`, neither field is shown to you"; "If the session is
  idle, the response waits until the next user interaction"; "In non-interactive mode with the `-p`
  flag, Claude Code kills any async hook still running at teardown"; "Once an async hook is running
  in the background, Claude Code doesn't enforce `timeout` on it". The same page's `PostToolUse`
  output table: `additionalContext` is "added to Claude's context alongside the tool result".
- **As of**: 2026-09-28.
- **Recheck trigger**: that section changes when async output is delivered, whether `-p` waits for
  a running async hook, or whether `timeout` applies to one; or this hook's measured Windows cost
  on a clean edit exceeds one second.

## License

MIT (SPDX-License-Identifier: MIT).
