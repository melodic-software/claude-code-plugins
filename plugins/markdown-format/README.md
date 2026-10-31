# markdown-format

A Claude Code plugin that formats Markdown with
[`markdownlint-cli2 --fix`](https://github.com/DavidAnson/markdownlint-cli2) in two
places. In a session it rewrites the `.md` and `.mdc` files a batch of tool calls wrote,
once per batch, and says nothing. At `git commit` a pre-commit entry rewrites the staged
Markdown, re-stages it, and blocks the commit only on a finding the commit adds. The
entry covers every author, people and other agents included, so findings reach whoever
commits and no finding reaches Claude per edit.

It uses **your repository's own markdownlint configuration**. It ships none and imposes
no rules of its own. A repository with no discoverable markdownlint config has chosen no
Markdown style, so nothing runs there. Carrying a config **is** the opt-in.

## Behavior

- **One rewrite per batch.** `hooks.json` registers one `PostToolBatch` row. The event has
  no matcher, so the launcher flag `--skip-unless-stdin-contains .md` ends the row before
  bash starts when the batch never mentions `.md`. The script then reads the `Write`,
  `Edit` and `MultiEdit` calls in the batch, rewrites the `.md` and `.mdc` files they
  named, once per repository root, and prints nothing. A file that only a `Read` named is
  never rewritten.
- **Config opt-in.** A file is touched only when a markdownlint config that
  `markdownlint-cli2` discovers on its own (`.markdownlint-cli2.jsonc`,
  `.markdownlint.json`, and the other documented names) exists between the file's
  directory and the repository root. A nested config governs its subtree. A
  `package.json` `markdownlint-cli2` property does not open the gate:
  markdownlint-cli2 honors it only under an explicit `--config` flag. Both the batch row
  and the pre-commit entry read the same gates (`git-hooks/markdown-gates.sh`).
- **A config that can run code waits for your approval.** `markdownlint-cli2` loads
  `.cjs` and `.mjs` configuration, custom rules, Markdown-it plugins and output formatters
  through Node's module loader, so running it under such a config executes code the
  repository supplies. A `.cjs` or `.mjs` config and a config naming `customRules`,
  `markdownItPlugins` or `outputFormatters` count. Until you approve that config state,
  the files it governs are neither rewritten nor checked: the pre-commit entry prints a
  trust-gate line and the batch row stays silent. See [Trust model](#trust-model).
- **Gitignored paths are out of scope for the batch row.** A file git excludes, a scratch
  tier such as `.work/**`, build output, or a vendored tree, is not rewritten. The verdict
  comes from `git check-ignore`: every `.gitignore` between the file and the repository
  root, `$GIT_DIR/info/exclude`, and your global `core.excludesFile`. A **tracked** file is
  never treated as ignored. Set `markdown_format_lint_gitignored` to `true` to bypass this
  check; markdownlint-cli2's own `ignores` / `gitignore` config still applies. The
  pre-commit entry only sees files git stages, so it needs no such rule.
- **Write paths the batch row does not see.** It reads only `Write`, `Edit` and `MultiEdit`
  calls. A file written through `Bash`, `PowerShell` or an MCP tool is not rewritten in
  the session; the pre-commit entry formats it at commit.
- **Files under `.githooks/` are never rewritten.** They are installed copies of check
  scripts.
- **The batch row needs a git working tree.** The file must sit inside one (or inside
  `CLAUDE_PROJECT_DIR`); a scratch file outside any repository is left alone.
- **Silence does not mean it ran.** The batch row prints nothing, and so do the policy
  skips: no markdownlint config, an unapproved code-capable config, a gitignored path. To tell the
  cases apart, check the file or run `/markdown-format:check`.
- **No per-edit findings.** Claude learns of a rewrite at its next edit of the file, which
  reports that the file changed on disk. Unfixable findings are reported at commit, as
  `<path>:<line>: <message>` on stderr with exit 1, only for lines the commit adds.

## Trust model

Neither the batch row nor the pre-commit entry runs `markdownlint-cli2` under a
code-capable config without an explicit approval of that exact content state. A person's
commit gets a trust-gate line naming the config and the approval marker to create; an
agent commit's line says the run was skipped and that approval is yours, without the
command that grants it. To approve, review the config and every module it references,
with the trust you give your build and CI configuration, then create the marker directory
with the exact `mkdir -p` command your notice carries. The marker lives under the
repository's git common directory, in `markdown-format/trust-approvals`, so one approval
covers the batch row, the end-of-turn row, an agent's commit and your own.

The marker is content-addressed over the repository, every governing code-capable config,
and every repository file those configs reference by a string literal or path-shaped
token (transitively, bounded at 64 files), so a change to any of them, including a branch
switch that swaps module bytes under an unchanged config, revokes the approval. Detection
is a text scan, so some states get no approval route and stay skipped: a config with a
backslash inside a quoted string or, in YAML, an escaped line join or a `!!` tag (it can
spell a key the scan cannot see); a JavaScript config or module that builds a path (the
`path` module, string concatenation, a template, `__dirname`, `process`) or calls a loader
with an argument the scan cannot read; a `.cjs` or `.mjs` cli2 config that names
`customRules`, `markdownItPlugins` or `outputFormatters`; a symlinked module, or one that
resolves outside the repository. Use a declarative JSONC or YAML config, with custom rules
named there, to stay covered.

## Git pre-commit entry

`git-hooks/markdown-check.sh` is the entry `markdown-check`. At commit it:

1. refuses a partly staged Markdown file untouched, with
   `<path>: partly staged; format it or stage it fully, then commit`;
2. runs `markdownlint-cli2 --fix` over the staged `.md` and `.mdc` files a config governs,
   then re-stages the files it rewrote;
3. blocks the commit on a finding that sits on a line the commit adds.

`/markdown-format:setup apply install-git-hooks [scope=local|shared]` registers it with
lefthook, husky or plain git hooks, and `/markdown-format:setup check` reports drift. A
missing `markdownlint-cli2` follows the check-placement contract: an agent commit fails
with the install command, a person gets a notice, and `git -c
checks.skipmissing=markdownlint-cli2 commit` skips it once.

A `Stop` row runs the same script with `--worktree`: when a turn ends it checks the
uncommitted changes and rewrites nothing. The `markdown_format_end_of_turn` option picks what
happens to the findings:

- **Unset (the default):** a warning shows you the findings, and the turn ends. Claude does
  not see them. The row exits 0 with a `systemMessage`.
- **`true`:** the findings go back to Claude, which keeps working to fix them, at most once
  per turn. The row exits 2.
- **`false`:** the row runs no check.

A missing `markdownlint-cli2` stays quiet here, since the `SessionStart` probe reports it.

## Requirements

- [Node.js](https://nodejs.org/) on `PATH`. Every hook row starts through
  `hooks/exec-bash.mjs`, so without `node` the hooks do not launch and nothing is
  enforced. `/markdown-format:check` reports it.
- Bash 3.2 or later. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run this Bash hook; WSL is also supported.
- [`jq`](https://jqlang.org/) to read the tool calls in a batch. Without it the batch row
  does nothing.
- [`git`](https://git-scm.com/) for the batch row's scope checks and for the pre-commit
  entry.
- [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2), installed
  explicitly either on `PATH` or as a pinned dependency in the consuming repository. For
  the latter, the plugin uses the extensionless `node_modules/.bin/markdownlint-cli2`
  shim that npm supplies for POSIX shells and Git Bash, found by walking up from the file
  to the repository root. It resolves symlinks first and rejects a shim whose physical
  target escapes the repository's `node_modules` tree. The plugin never falls back to
  `npx`, installs a package, or touches the network.

A missing `markdownlint-cli2` or `jq` is reported once per session by the `SessionStart`
probe (`lib/prerequisites.mjs probe`), which also reports a missing, stale or edited
git-hook entry. The probe honors `markdown_format_enabled` and does not look for a
markdownlint config, so it can report in a repository that has none.

### Hook budget accounting

Per [`docs/contracts/hook-budget/README.md`](../../docs/contracts/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch
of every session. Its launcher flag `--skip-unless-stdin-contains .md` closes before bash
starts when the payload never mentions `.md`. Measured on WSL2 Ubuntu (bash 5.3.9,
markdownlint-cli2 0.23.3, node 24) on 2026-10-15, with the row launched as `hooks.json`
registers it, ten fires per case; spawns are from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| No `.md` in the payload | 0.057 s | 0.050-0.062 s | 1 (the `node` launcher) |
| A `Read` of a `.md` file, nothing to rewrite | 0.076 s | 0.060-0.096 s | 6 |
| One `Edit` of a `.md` file that needs a rewrite | 0.446 s | 0.389-0.623 s | 21 |

The ceiling for a per-batch formatter row is 1 s median per fire, so the row ships.
`.performance/ratchets.json` holds the no-Markdown row at 1 spawn, and the `Stop` row with
`markdown_format_end_of_turn` set to `false` at 1 spawn. The remaining time of the
rewrite case is `markdownlint-cli2` itself, one Node process per root.

With the option unset, its default, the `Stop` row starts bash and the check script on every
turn end. On a clean tree that costs 20 spawns (11 creations, 9 execs) and 45.6 ms mean against
25.3 ms with the option `false` (WSL2 Ubuntu, `hyperfine -N`, 60 runs each), held at 20 spawns in
`.performance/ratchets.json`. On Windows (Git Bash 5.3.15, 40 runs each) the same path takes 447.5 ms
mean against 90.6 ms with the option `false`, about 357 ms per turn end: inside the 2,000 ms Stop
wall and the 1 s per-fire ceiling, and the spawn count is what any reduction would cut.

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
To change the rules, edit your repo's markdownlint config. To exempt a path that git
tracks, use `markdownlint-cli2`'s own `ignores` (or `gitignore`) key in a
`.markdownlint-cli2.*` config; both the batch row and the pre-commit entry pass each file
as a literal path, and markdownlint-cli2 applies those keys itself (verified against
markdownlint-cli2 v0.23.3).

Three `userConfig` options tune the hooks:

| Option | Type | Default | Effect |
|--------|------|---------|--------|
| `markdown_format_enabled` | boolean | `true` | Kill switch for the hooks. Set `false` for a clean no-op. |
| `markdown_format_lint_gitignored` | boolean | `false` | Bypass the batch row's git-ignore check. Off by default: an excluded path is not rewritten. It does not override markdownlint-cli2's own `ignores` / `gitignore` config. |
| `markdown_format_end_of_turn` | boolean | unset | Run the pre-commit check over the uncommitted changes when a turn ends. Nothing is rewritten. Unset, a warning shows you the findings and the turn ends; `true` hands them back to Claude once per turn; `false` runs no check. |

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
| `markdown_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED` | Rewrite the Markdown files a batch of tool calls wrote (runs only when the repo carries a markdownlint config) |
| `markdown_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED` | By default the hook leaves gitignored files alone: a scratch tier the repo excludes is not rewritten. Set true to bypass this hook's git check; markdownlint-cli2's own ignores and gitignore config still apply, so a path your markdownlint config excludes stays untouched. |
| `markdown_format_end_of_turn` | boolean | *(none)* | `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN` | When a turn ends, run the pre-commit check over the uncommitted changes; nothing is rewritten. Unset (the default) shows markdownlint findings to you in a warning and the turn ends. true hands them back to Claude, at most once per turn. false runs no check. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure markdown-format@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure markdown-format@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"markdown_format_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install markdown-format@<marketplace> -s <scope> --config markdown_format_enabled=<value>
   ```

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

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
