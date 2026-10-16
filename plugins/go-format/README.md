# go-format

A Claude Code plugin that formats Go files and manages their imports with
[goimports](https://pkg.go.dev/golang.org/x/tools/cmd/goimports) in two places: once per batch of
tool calls in a Claude Code session, and again at git pre-commit for every author. Both run
`goimports -w`, which adds missing imports, removes unused ones, and applies `gofmt`-equivalent
formatting. `goimports` reports no lint findings; a file it cannot parse is the only failure, and
the pre-commit entry reports it.

## Behavior

- **One rewrite per batch, silent.** A `PostToolBatch` row runs after the tool calls of a turn
  step resolve. It takes the `.go` files that `Write`, `Edit` or `MultiEdit` calls in the batch
  named, and runs `goimports -w` once over all of them. It prints nothing and exits `0`: no
  finding and no notice goes to Claude or the user. A file that `Read` named is never rewritten,
  and a file `goimports` cannot parse is left as it is.
  - The row has no matcher or `if` (neither applies to `PostToolBatch`). Its launcher skips the
    script unless the payload mentions `.go`, so a batch without Go costs one `node` process.
  - **Pointer**: when deciding what filters a `PostToolBatch` row, fetch
    [hooks: PostToolBatch](https://code.claude.com/docs/en/hooks#posttoolbatch) live.
    **As of**: 2026-10-15. **Recheck trigger**: that section adds a matcher or an `if` for the
    event, or changes the `tool_calls` fields.
- **No consumer-config opt-in gate.** Unlike sibling formatter plugins (`ruff-format`,
  `typos-format`), this plugin needs no repository configuration to run on a `.go` file.
  `goimports`' own docs describe it as "a replacement for your editor's gofmt-on-save hook" and it
  has no meaningful config-divergence axis when left unconfigured. Running it does not impose a
  style choice a repo hasn't made, the same reasoning that makes `gofmt` itself safe to run
  unconditionally.
- **Skips generated files.** A file whose leading comment/blank-line block contains Go's
  canonical `// Code generated ... DO NOT EDIT.` marker is left untouched, in the session and at
  commit. This includes files where a copyright/license header (a `//` or `/* */` block) precedes
  the marker, common for `addlicense`/`goheader` output. `goimports` itself has no awareness of
  that convention, so the plugin adds the guard itself.
- **Leaves gitignored files alone.** By default a `.go` file the repository gitignores is not
  rewritten in the session, since a rewrite of an ignored file has no git checkout to undo it. A
  tracked file that matches an ignore pattern stays in scope. Set `go_format_lint_gitignored=true`
  to act on gitignored files too. Files under `.githooks/` (installed copies) are always skipped.
- **Groups local imports using your module's own path.** When a `go` toolchain is on `PATH`, both
  places resolve the file's own module path (`go list -m`) and pass it as goimports' `-local`
  grouping prefix, so your package's own internal imports stay in their own group instead of being
  collapsed into the third-party group, without adding any new consumer config. Falls back to
  goimports' plain default grouping when `go` is absent or the file isn't in a resolvable module.
- **Opt-in end-of-turn check.** With `go_format_end_of_turn` set to `true`, a `Stop` row parses
  the Go files changed since the last commit (untracked files included), rewrites nothing, and
  hands back any file `goimports` cannot parse, so it is fixed before the turn ends. It blocks at
  most once per turn. Off by default.

## Git pre-commit entry

The plugin ships one git-hook entry, `goimports-format` (`git-hooks/entries.json`), which
rewrites. At commit it refuses a partly staged Go file untouched, runs `goimports -w` over the
staged `.go` files, re-stages what changed, and blocks the commit only when `goimports` itself
fails, which it does for a file it cannot parse. Each failure prints as
`<path>:<line>: <message>`; a file that does not parse blocks wherever the error sits. It reaches
every author, not only Claude, once `/go-format:setup apply install-git-hooks [scope=local|shared]`
registers it with the repository's hook manager (lefthook, husky or plain git hooks). Local scope
stays in this clone; shared scope commits the copy under `.githooks/go-format/`.
`/go-format:setup check` reports drift, and the SessionStart probe prints one line when the entry
is missing, stale or edited.

When `goimports` is missing, the entry follows the check-placement convention: an agent commit
fails with the install command, a person gets a one-line notice, and
`git -c checks.skipmissing=goimports commit ...` skips it with a printed line.

## Requirements

- **Bash.** The hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`. Without
  node the hooks do not start and nothing is enforced.
- **jq** on `PATH`. The batch row reads the file paths with it. Absent: the row does nothing.
  [Install jq](https://jqlang.org/download/).
- **goimports** on `PATH`. Like `typos-format`, `goimports` has no
  per-repo dependency-manager convention. It is conventionally
  `go install`ed to the machine-global `$GOPATH/bin`. It is never
  downloaded on the fly; if it is not present, the batch row skips the files, and the
  SessionStart probe reports the gap.
  [Install](https://pkg.go.dev/golang.org/x/tools/cmd/goimports):
  `go install golang.org/x/tools/cmd/goimports@latest` (requires a
  [Go toolchain](https://go.dev/dl/)).
- **`go` on `PATH` (optional).** Used only to resolve the `-local` grouping
  prefix (`go list -m`). Absent: `goimports` still formats and fixes imports, just
  without the `-local` grouping (its plain default behavior).

A `SessionStart` probe reports a missing `goimports` wherever the plugin is enabled and
`go_format_enabled` is not `false`, including a repository with no `.go` files, and names
`/go-format:check`. It installs nothing.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the `PostToolBatch` row is always-on: the event has no matcher, so it fires on every batch of every
session. Its launcher flag `--skip-unless-stdin-contains .go` closes before bash starts when the
payload never mentions `.go`. Measured on WSL2 Ubuntu (bash 5.3.9, goimports 0.52.0, go 1.27.2,
node 24) on 2026-10-15, with the row launched as `hooks.json` registers it, ten fires per case;
spawns are from `scripts/hook-census.sh`:

| Batch | Median wall | Min-max | Spawns |
| --- | --- | --- | --- |
| No `.go` in the payload | 0.042 s | 0.040-0.050 s | 1 (the `node` launcher) |
| A `Read` of a `.go` file, nothing to rewrite | 0.052 s | 0.043-0.063 s | 6 |
| One `Edit` of a `.go` file that needs a rewrite | 0.129 s | 0.111-0.166 s | 24 |

The ceiling for a per-batch formatter row is 1 s median per fire. The pre-commit entry on one
staged `.go` file that needs a rewrite takes a median 0.078 s (0.068-0.083 s). Fences:
`.performance/ratchets.json` holds the no-Go row at 1 spawn, and the Stop row with
`go_format_end_of_turn` off (its default) at 1 spawn.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install go-format@<marketplace>
```

Then verify prerequisites with `/go-format:setup check`.

## Configuration

There are no rules to configure. `goimports` runs with no consumer-config
surface to read. Three `userConfig` options tune the hooks themselves:

| Option | Default | Effect |
|--------|---------|--------|
| `go_format_enabled` | `true` | Kill switch. Set `false` for a clean no-op. |
| `go_format_lint_gitignored` | `false` | Set `true` to also act on files the repository gitignores. |
| `go_format_end_of_turn` | `false` | Set `true` to parse the uncommitted Go files when a turn ends; a file `goimports` cannot parse goes back to Claude once per turn. Nothing is rewritten. |

Set it interactively with `/plugin configure go-format@<marketplace>`, or headless on the
install command:

```shell
claude plugin install go-format@<marketplace> --config go_format_enabled=false
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `go_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED` | After each batch of tool calls, run goimports -w over the Go files it wrote |
| `go_format_lint_gitignored` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_GO_FORMAT_LINT_GITIGNORED` | By default the hook leaves a file the repository gitignores alone: it is not rewritten, since a rewrite of an ignored file has no git checkout to undo it. Set true to act on gitignored files too. A tracked file that matches an ignore pattern is always in scope. |
| `go_format_end_of_turn` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN` | At the end of each turn, run goimports over the Go files changed since the last commit and hand back any file it cannot parse, so it is fixed before the turn ends, at most once per turn. Nothing is rewritten. Off by default. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure go-format@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install go-format@<marketplace> -s <scope> --config go_format_enabled=<value>
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
       "go-format@<marketplace>": {
         "options": {
           "go_format_enabled": <value>
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
