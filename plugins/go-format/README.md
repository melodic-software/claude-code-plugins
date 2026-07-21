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
- **Skips generated files.** A file whose first non-blank line matches Go's
  canonical `// Code generated ... DO NOT EDIT.` marker is left untouched.
  `goimports` itself has no awareness of that convention, so this hook adds
  the guard itself.
- **Fix in place.** Formatting and import changes are applied silently — no
  advisory noise on a successful fix, the same posture as a successful
  `ruff-format`/`typos-format` autofix pass.
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

Set it interactively with `/plugin configure go-format`, or headless on the
install command:

```shell
claude plugin install go-format@melodic-software --config go_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To turn the plugin off for a single repository, disable it in
that project's `enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
