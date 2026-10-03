# markdown-format

A Claude Code plugin that auto-formats and lints Markdown the moment you edit it.
On every `Write` or `Edit` of a `.md` or `.mdc` file it runs
[`markdownlint-cli2 --fix`](https://github.com/DavidAnson/markdownlint-cli2) from
the file's repository root, applying every auto-fixable rule and surfacing the
residual (unfixable) findings back to Claude as advisory context.

It uses **your repository's own markdownlint configuration**. It ships none and
imposes no rules of its own. A repository with no discoverable markdownlint
config has chosen no Markdown style, so the hook does not run there at all
(#1809): carrying a config **is** the opt-in.

## Behavior

- **Markdown paths only at launch.** `hooks.json` registers the handler on
  `Write|Edit` but each copy carries `if: Edit(*.md)` or `if: Edit(*.mdc)`.
  `Edit(path)` is the permission-rule form that covers Write; a `Write(path)`
  rule is never matched. A `.txt` Write therefore never starts the process.
  It does not reach the script's in-script extension skip, and it cannot
  produce a `hook_non_blocking_error` for work this hook does not do (#2867).
  The script still checks the extension itself, because the hooks reference
  calls the `if` filter best-effort. Its one documented fail-open is for Bash
  input it cannot parse, and it documents no file-tool equivalent
  ([hooks reference](https://code.claude.com/docs/en/hooks), common fields,
  checked 2026-09-27).
- **Config opt-in.** The hook runs only when a markdownlint config file that
  `markdownlint-cli2` would discover automatically (`.markdownlint-cli2.jsonc`,
  `.markdownlint.json`, …, any of the ten documented names) exists between the
  edited file's directory and the repository root. Without one, neither `--fix`
  rewrites nor default-rule findings are imposed, the same doctrine as
  `bash-format`'s shfmt gate. A `package.json` `markdownlint-cli2` property
  does not open the gate: markdownlint-cli2 honors it only under an explicit
  `--config` flag, not by discovery. A file under no git working tree has no
  repository root, so when `CLAUDE_PROJECT_DIR` is set the walk stops there
  instead, which lets an unpacked or vendored project's root config opt it in.
  A config in your home directory or above it never does on that path: a
  session started in `~` would otherwise let a personal
  `~/.markdownlint-cli2.jsonc` rewrite every `.md` under home. A config inside a
  working tree, a dotfiles repository rooted at `~` included, is unaffected.
- **Gitignored paths are out of scope.** A file git excludes, a scratch tier
  such as `.work/**`, build output, or a vendored tree, is neither rewritten nor
  reported on. Your ignore rules already say which paths are not part of the
  reviewable artifact, so the hook reads them rather than asking for a second
  declaration. The verdict comes from `git check-ignore`, so it is git's full
  exclude machinery, not `.gitignore` alone: every `.gitignore` between the file
  and the repository root, `$GIT_DIR/info/exclude`, and your global
  `core.excludesFile`. A **tracked** file is never treated as ignored, even when
  a pattern matches it. Set `markdown_format_lint_gitignored` to `true` to bypass
  **this hook's** git check. That is the only thing it bypasses:
  markdownlint-cli2 applies its own `ignores` / `gitignore` config downstream, so
  a path your markdownlint config also excludes stays untouched even with the
  option on. When the verdict cannot be determined (no `git` on
  `PATH`, no working tree, `git check-ignore` erroring), the hook lints. A
  scope check that failed closed would disable the plugin invisibly.
- **Auto-fix on edit.** Fixable violations (final newline, list-marker style,
  trailing spaces, …) are corrected in place, and the count of fixes written is
  reported to Claude and to you. A run that changed your file never passes
  unannounced. `markdownlint-cli2` reports no per-fix detail, so neither can
  this hook; the count is what there is.
- **Advisory, never blocking.** The hook always exits `0`. Unfixable findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.
- **Silence does not mean it ran.** A clean run prints nothing, and so do the
  policy skips: no markdownlint config, a gitignored path, and (when
  `CLAUDE_PROJECT_DIR` is unset) a file outside every git working tree. From
  the session, a hook that linted a clean file and a hook that never linted
  look the same. Only missing prerequisites and the trust gate announce
  themselves, by class. A missing `markdownlint-cli2` is a prerequisite notice:
  once per session (a subagent does not repeat it), renewed with the install
  route every eighth skip (`HOOK_NOTICE_RENEW_EVERY`). The missing-`jq` notice and
  the trust-gate notice are once per session and agent, renewed every eighth
  skip. Silent in between. To tell the cases apart, wire a
  [telemetry sink](../../docs/conventions/hook-telemetry/README.md) through
  `HOOK_TELEMETRY_SINK`: each run's envelope carries `status` `ok` for a lint
  that ran and `skipped` for every skip arm.
- **Bounded reporting.** Every run reports the total finding count and the rules
  that dominate it. Individual violation lines are capped (20 by default,
  `markdown_format_max_findings`), and an unchanged finding set on a re-edited
  file reports its summary without repeating the detail. The linter's own banner
  lines never enter the report. A rule firing in bulk is a signal to configure
  that rule once in your markdownlint config, not to re-read it on every edit.
- **Config from the consumer.** `markdownlint-cli2` discovers config
  (`.markdownlint-cli2.jsonc`, `.markdownlint.json`, …) per edited file, from
  the file's directory up through its parents, so a nested config governs its
  subtree. The hook `cd`s to the repository root before linting so that
  discovery caps at the root regardless of the session's working directory.
  A configuration that can execute code is gated on explicit approval. See
  [Configuration trust boundary](#configuration-trust-boundary).

## Known limitations

Claude Code runs every matching `PostToolUse` hook in parallel, with no
locking/ordering primitive. In an opted-in repo this hook is the single
in-place rewriter for `.md`/`.mdc` by default; a consumer who ALSO opts
`typos-format`'s write mode on accepts **last-writer-wins** ordering between
the two on every Markdown edit. The residual overlap class across scoped
writer hooks is tracked fleet-wide in #875.

**Write paths the hook does not see.** The matcher is `Write|Edit`, so only
those two tools reach it. A Markdown file written through the `Bash` tool (a
heredoc, a redirect, `sed -i`), through `PowerShell`, or through an MCP
filesystem server's write tool is never formatted or linted. `guardrails`'
`block-hook-bypass`, when installed, blocks the common Bash redirect and
heredoc forms, `python3 -c` writes that use a file-write call it recognizes,
and the PowerShell write cmdlets; `sed -i`, `perl -i`, `tee`, a standalone
`cp`, and other interpreters' one-liners such as `node -e` are outside what it
detects, and it does not see MCP tools. CI is the only gate that sees every
path. The matcher does not list
`MultiEdit`: the [tools reference](https://code.claude.com/docs/en/tools-reference)
does not list it among the built-in tools, and
[permissions](https://code.claude.com/docs/en/permissions) calls it "the legacy
`MultiEdit` tool" (both checked 2026-09-27; recheck if `MultiEdit` returns to
the tools reference).

**Timeout tail.** Each handler sets `"timeout": 15`, well under the 600-second
default for a command hook, and Claude Code discards the output of a hook it
cancels at its timeout ([hooks reference](https://code.claude.com/docs/en/hooks),
"Timeouts", checked 2026-09-27). `markdownlint-cli2 --fix` rewrites the file in
place before the hook composes its report, so a cancel between the two leaves
your file rewritten with no disclosure on either channel. This window has not
been reproduced; a clean run costs about 2.6 s of reference-host work in
the cost table below, well inside 15 s. If you see a
Markdown file change after an edit with no `markdown-format rewrote` notice,
this is the likely cause.

## Requirements

The hook requires the following tools:

- [Node.js](https://nodejs.org/) on `PATH`. Every hook row starts through
  `hooks/exec-bash.mjs`, so without `node` the hooks do not launch and nothing is
  enforced. `/markdown-format:check` reports it.
- Bash 3.2 or later. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run this Bash hook; WSL is also supported.
- [`jq`](https://jqlang.org/) to parse hook input and emit structured context.
- [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2),
  installed explicitly either on `PATH` or as a pinned dependency in the consuming
  repository. For the latter, the hook uses the extensionless
  `node_modules/.bin/markdownlint-cli2` shim that npm supplies for POSIX shells and Git
  Bash. It resolves symlinks first and rejects a shim whose physical target escapes the
  repository's `node_modules` tree.

Missing prerequisites do not block an edit. Following Claude Code's
[PostToolUse contract](https://code.claude.com/docs/en/hooks#posttooluse-decision-control),
the hook exits `0` and reports a notice to both Claude (`additionalContext`)
and you (`systemMessage`). A missing-`markdownlint-cli2` notice is shown once
per session, not per subagent, and renewed with the install route every eighth
skip (`HOOK_NOTICE_RENEW_EVERY`). The `SessionStart` probe below uses the same
notice key, so its notice counts as skip number one, the first per-edit skip is
number two and stays silent, and the next per-edit notice appears at the eighth
skip. The missing-`jq` notice and the trust-gate notice are once per session and
agent, renewed every eighth skip.
The binary probe re-runs on every Markdown edit and recovers mid-session when
the tool becomes resolvable. A missing-`markdownlint-cli2` notice includes a
`PATH probed:` line naming the plausible directories the hook process actually
searched (Claude Code plugin-bin entries collapse to a count). When
the edited file is outside a repository the notice names a durable user-scope
directory already on that PATH instead of recommending a repo-local
`npm i -D`. The hook never falls back to `npx`, installs a package, or
performs a network request during a hook run.

`hooks/hooks.json` also registers a `SessionStart` probe. It reads
`prerequisites.json` and reports a missing `markdownlint-cli2` at session start,
and it honors `markdown_format_enabled`. `/markdown-format:check` is the
read-only check that notice names. The probe does not look for a markdownlint
config, so it can report in a repository that has none.

`jq` is deliberately absent from `prerequisites.json`. That manifest drives the
session-start probe, which does not consult the per-repo config opt-in, while the
missing-`jq` notice comes only from the per-edit hook after its opt-in pre-check
(`markdown-format.sh`, `hook::require jq` after the config walk). Listing `jq`
would announce it in repositories that never opted in.

Telemetry timing uses `EPOCHREALTIME` (Bash 5.0+); on older Bash the telemetry
envelope is skipped while formatting still runs.

`git` is **not** required. Without it, formatting and linting still run; three
things that ask git a question degrade instead of blocking: the gitignore scope
lints rather than skipping (as above), the working-tree scope that applies when
`CLAUDE_PROJECT_DIR` is unset stops narrowing anything (config discovery is then
anchored at the edited file's own directory, so it opens only for a config
sitting there), and the repeat-report suppression stops deduplicating, so an
unchanged finding set is reported in full each time.

### Configuration trust boundary

`markdownlint-cli2` supports executable `.cjs`/`.mjs` configuration and can
load custom rules, Markdown-it plugins, and output formatters. Running it
under such configuration executes code the repository supplies. The hook
therefore never runs the linter under a code-loading configuration without an
explicit approval: it skips the lint run and reports a visible trust-gate
notice (on both the agent and user channels, renewed like the
missing-prerequisite notice) naming the
risky files and the approval marker to create. To approve, review those files
and their installed dependencies, then create the marker directory using the
exact `mkdir -p` command the notice carries. The marker lives under
`${CLAUDE_PLUGIN_DATA}/trust-approvals` and is content-addressed over the
repository, its risky configuration files, and every repository file those
files' string literals resolve to (transitively, bounded), so a change to the
configuration or to a referenced repository module, including a branch switch
that swaps module bytes under an unchanged config, revokes the approval and
re-gates the run. When `CLAUDE_PLUGIN_DATA` is unavailable, the module scan
overflows its bound, or the configuration contains constructs that defeat
textual verification (string escapes or tags able to hide a module-loading
key), the gate fails closed and the lint run stays skipped. Declarative
rule-only JSONC/YAML configuration is unaffected and lints immediately.
Prefer it when executable configuration is unnecessary.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
this hook is always-on for every `Write` and `Edit` of a `.md` or `.mdc` file (the two `if`
rows in `hooks/hooks.json` keep every other extension from spawning it), so its cost on a clean
Markdown edit is the figure that counts. Measured on Windows 11 under Git Bash, twelve interleaved
trials against an interleaved `bash -c :` floor (2026-09-02). These figures predate the `node`
launcher (`hooks/exec-bash.mjs`) and the `SessionStart` probe: each fire now adds one `node`
process before `bash`, and the figures have not been re-measured. The `SessionStart` probe is
exec form, so its k is 1 (the launcher); it then runs `bash` and `probe-prerequisite.sh` once
per session start. It is not measured here:

| Event | Fires | Spawn-equivalents | What changed |
| --- | --- | --- | --- |
| PostToolUse `Write`, clean `.md` in a repo with a markdownlint config | 1 | 41.6 before, 32.0 after (0.11.38) | seven of twenty-one processes gone: six `dirname` calls and one `basename` are parameter expansions, including inside the config-discovery and risky-config walks |
| PostToolUse `Write`, non-Markdown file | 0 | skipped by the `if` rows | one entry per extension since 0.11.35 |

The residual is `markdownlint-cli2` itself (one Node process per fire) plus the shared library's
payload reader and telemetry emitter, cut in 0.11.39 by the vendored `hook-utils.sh`. 0.11.51
drops leftover helper-capture and dirname forks on the root-resolution path
(`resolve_repo_root_to`, jq-absent opt-in probe, membership dirname); physical `pwd -P`
containment stays.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install markdown-format@<marketplace>
```

Then verify the runtime prerequisites with `/markdown-format:setup check`;
`/markdown-format:setup apply` resolves anything the check reports with
guidance, and `/markdown-format:setup apply install-lint` additionally
authorizes installing `markdownlint-cli2` as a dev dependency using the
repository's own package manager.

## Configuration

The rules themselves are never configured here. The plugin's only rule source is
the markdownlint config already in your repository, which it reads automatically.
To change the rules, edit your repo's markdownlint config.

Which paths are in scope is also not configured here: the hook asks
`git check-ignore` and leaves the paths git excludes alone. That means your
`.gitignore` files, `$GIT_DIR/info/exclude`, and your global `core.excludesFile`
together. To exempt a path that git tracks, use `markdownlint-cli2`'s own
`ignores` (or `gitignore`) key in a `.markdownlint-cli2.*` config. The hook
passes the edited file to
`markdownlint-cli2`, which applies those itself (verified against
markdownlint-cli2 v0.23.2; the tool's documentation does not state the behavior
for an explicitly named file, so confirm it against your own version).

Three `userConfig` options tune the hook itself:

| Option | Type | Default | Effect |
|--------|------|---------|--------|
| `markdown_format_enabled` | boolean | `true` | Toggle the markdown-format hook; set `false` for a clean no-op. |
| `markdown_format_lint_gitignored` | boolean | `false` | Bypass this hook's git-ignore check. Off by default: an excluded path is neither rewritten nor reported on. Turning it on does not override markdownlint-cli2's own `ignores` / `gitignore` config, which still applies. |
| `markdown_format_max_findings` | number | `20` | How many individual violations are listed per run. The total count and the leading rule codes are always reported regardless. `0` = unlimited. |

Set them interactively with `/plugin configure markdown-format@<marketplace>`, or headless on
the install command:

```shell
claude plugin install markdown-format@<marketplace> --config markdown_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `markdown_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED` | Auto-format and lint Markdown on Write/Edit of .md/.mdc files (runs only when the repo carries a markdownlint config) |
| `markdown_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED` | By default the hook leaves gitignored files alone: a scratch tier the repo excludes is neither rewritten nor reported on. Set true to bypass this hook's git check; markdownlint-cli2's own ignores and gitignore config still apply, so a path your markdownlint config excludes stays untouched. |
| `markdown_format_max_findings` | number<br>*min 0* | `20` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS` | How many individual markdownlint violations are listed per run. The total count and the leading rule codes are always reported regardless. 0 = unlimited. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure markdown-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install markdown-format@<marketplace> -s <scope> --config markdown_format_enabled=<value>
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
       "markdown-format@<marketplace>": {
         "options": {
           "markdown_format_enabled": <value>
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

This plugin's PostToolUse hook is filtered to `*.md` and `*.mdc` by an `if`
condition on its two `Write|Edit` rows, so it costs nothing on any other file.
On a Markdown edit it owes the marketplace's
[hook budget](../../docs/conventions/hook-budget/README.md) an honest figure. The figures below
predate the `node` launcher and the `SessionStart` probe (see
[Hook budget accounting](#hook-budget-accounting)).

**Method.** `EPOCHREALTIME` wall-clock around a direct hook invocation, 12
interleaved trials, each preceded by a `bash -c :` spawn-floor run so the
reported ratio absorbs machine load. The payload is a `PostToolUse` `Write`
naming a clean scratch `.md` inside a repository that has a markdownlint config,
so the lint finds nothing and the hook takes the path that runs on nearly every
Markdown edit. Windows 11 + Git Bash, 2026-09-02.

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
| Clean `.md`, before (0.11.36) | 41.6 | ≈ 3,328 ms | 21 | 33 |
| Clean `.md`, after (0.11.38) | 32.0 | ≈ 2,560 ms | 14 | 29 |
| Non-Markdown file, after | 4.4 | ≈ 352 ms | 1 | 9 |

**A clean Markdown edit costs ≈ 32.0 spawn-equivalents, ≈ 2,560 ms of
reference-host work, down 23 percent.** Six `dirname` calls and one `basename`
became parameter expansions, including inside the two directory walks whose
exec count grew with the file's depth below the repository root.

The non-Markdown row measures the in-script extension guard on its own. In a
live session the `if` condition rejects that payload before this hook is
spawned at all, so the row exists to show the guard is independently correct,
not to describe a cost anyone pays.

**Residual, and why it stays.** The dominant single cost is `markdownlint-cli2`,
a Node process, which is the point of the hook. Of the remaining thirteen
processes, eight to ten belong to the shared `hooks/hook-utils.sh`: payload
validation, the `file_path` read and its project-membership scoping, and the
repository-root lookup. That file is a registered byte-identical cross-plugin
cluster, so changing it is a nine-plugin change and not this plugin's to make.
Two `git` calls resolve the repository root and the gitignore verdict. Two
`grep` calls scan the applicable markdownlint config for the keys that would let
it load code; those were left alone deliberately, because they run different
line-anchored patterns with different outcomes and a whole-file match in bash
would change `$` from end-of-line to end-of-string. They are worth about 1.4
spawn-equivalents, which does not buy that semantic risk.

## License

MIT (SPDX-License-Identifier: MIT).
