# go-format

A Claude Code plugin that formats Go files and manages their imports the
moment you edit them. On every `Write` or `Edit` of a `.go` file it runs
[goimports](https://pkg.go.dev/golang.org/x/tools/cmd/goimports)'s `-w`,
which adds missing imports, removes unused ones, and applies `gofmt`-
equivalent formatting — then surfaces any syntax error goimports can't parse
back to Claude as advisory context.

## Behavior

- **Unconditional — no consumer-config opt-in gate.** Unlike sibling
  formatter plugins (`ruff-format`, `typos-format`), this hook runs on every
  edited `.go` file regardless of repository configuration. `goimports`'
  own docs describe it as "a replacement for your editor's gofmt-on-save
  hook" and it has no meaningful config-divergence axis when left
  unconfigured — running it does not impose a style choice a repo hasn't
  made, the same reasoning that makes `gofmt` itself safe to run
  unconditionally.
- **Extension-scoped.** Only `.go` files trigger the hook (like
  `ruff-format`'s `*.py`/`*.pyi` filter; unlike `typos-format`'s
  language-agnostic scope).
- **Skips generated files.** A file whose leading comment/blank-line block
  contains Go's canonical `// Code generated ... DO NOT EDIT.` marker is
  left untouched — this includes files where a copyright/license header
  (a `//` or `/* */` block) precedes the marker, common for
  `addlicense`/`goheader` output. `goimports` itself has no awareness of
  that convention, so this hook adds the guard itself.
- **Fix in place.** Formatting and import changes are applied silently — no
  advisory noise on a successful fix, the same posture as a successful
  `ruff-format`/`typos-format` autofix pass.
- **Groups local imports using your module's own path.** When a `go`
  toolchain is on `PATH`, the hook resolves the edited file's own module
  path (`go list -m`) and passes it as goimports' `-local` grouping prefix,
  so your package's own internal imports stay in their own group instead of
  being collapsed into the third-party group — matching goimports' own
  `-local` convention without adding any new consumer config. Falls back to
  goimports' plain default grouping when `go` is absent or the file isn't
  in a resolvable module.
- **Syntax errors surface as advisory findings.** When `goimports` can't
  parse the file, the parse diagnostic is reported via `additionalContext`,
  never auto-"fixed" and never treated as a tool break.
- **Advisory, never blocking.** The hook always exits `0`. Findings are
  reported via `additionalContext`; they never reject the edit. Make a
  commit hook or CI your hard gate.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **goimports** on `PATH`. Like `typos-format`, `goimports` has no
  per-repo dependency-manager convention — it is conventionally
  `go install`ed to the machine-global `$GOPATH/bin`. It is never
  downloaded on the fly; if it is not present, the hook skips with a
  visible once-per-session notice.
  [Install](https://pkg.go.dev/golang.org/x/tools/cmd/goimports):
  `go install golang.org/x/tools/cmd/goimports@latest` (requires a
  [Go toolchain](https://go.dev/dl/)).
- **`go` on `PATH` (optional).** Used only to resolve the `-local` grouping
  prefix (`go list -m`). Absent: the hook still formats/fixes imports, just
  without the `-local` grouping (goimports' plain default behavior).

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while
formatting still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install go-format@melodic-software
```

Then verify prerequisites with `/go-format:setup check`.

## Configuration

There are no rules to configure — `goimports` runs with no consumer-config
surface to read. One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `go_format_enabled` | `true` | Kill switch — set `false` for a clean no-op. |

Set it interactively with `/plugin configure go-format@melodic-software`, or headless on the
install command:

```shell
claude plugin install go-format@melodic-software --config go_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To turn the plugin off for a single repository, disable it in
that project's `enabledPlugins` instead.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `go_format_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED` | Run goimports -w on edit of a Go file |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure go-format@<marketplace>`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install go-format@<marketplace> --config go_format_enabled=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
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
