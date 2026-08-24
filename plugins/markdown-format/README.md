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
  The script still checks the extension itself, because an `if` filter is one
  rule per handler and fails open on an unparsable payload.
- **Config opt-in.** The hook runs only when a markdownlint config file that
  `markdownlint-cli2` would discover automatically (`.markdownlint-cli2.jsonc`,
  `.markdownlint.json`, …, any of the ten documented names) exists between the
  edited file's directory and the repository root. Without one, neither `--fix`
  rewrites nor default-rule findings are imposed, the same doctrine as
  `bash-format`'s shfmt gate. A `package.json` `markdownlint-cli2` property
  does not open the gate: markdownlint-cli2 honors it only under an explicit
  `--config` flag, not by discovery.
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

## Known limitation

Claude Code runs every matching `PostToolUse` hook in parallel, with no
locking/ordering primitive. In an opted-in repo this hook is the single
in-place rewriter for `.md`/`.mdc` by default; a consumer who ALSO opts
`typos-format`'s write mode on accepts **last-writer-wins** ordering between
the two on every Markdown edit. The residual overlap class across scoped
writer hooks is tracked fleet-wide in #875.

## Requirements

The hook requires the following tools:

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
the hook exits `0` and reports a once-per-session notice to both Claude
(`additionalContext`) and you (`systemMessage`). Only the notice latches.
The binary probe re-runs on every Markdown edit and recovers mid-session when
the tool becomes resolvable. A missing-`markdownlint-cli2` notice includes a
`PATH probed:` line naming the plausible directories the hook process actually
searched (Claude Code plugin-bin entries collapse to a count). When
the edited file is outside a repository the notice names a durable user-scope
directory already on that PATH instead of recommending a repo-local
`npm i -D`. The hook never falls back to `npx`, installs a package, or
performs a network request during a hook run.

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
notice (once per session, on both the agent and user channels) naming the
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

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `markdown_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED` | Auto-format and lint Markdown on Write/Edit of .md/.mdc files (runs only when the repo carries a markdownlint config) |
| `markdown_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED` | By default the hook leaves gitignored files alone — a scratch tier the repo excludes is neither rewritten nor reported on. Set true to bypass THIS HOOK's git check; markdownlint-cli2's own ignores/gitignore config still applies downstream, so a path your markdownlint config also excludes stays untouched. |
| `markdown_format_max_findings` | number<br>*min 0* | `20` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS` | How many individual markdownlint violations are listed per run. The total count and the leading rule codes are always reported regardless. 0 = unlimited. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure markdown-format@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install markdown-format@<marketplace> -s <scope> --config markdown_format_enabled=<value>
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
       "markdown-format@<marketplace>": {
         "options": {
           "markdown_format_enabled": <value>
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
