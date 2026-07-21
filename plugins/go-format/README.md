# go-format

A Claude Code plugin that reformats Go source files the moment you edit them.
On every `Write` or `Edit` of a `.go` file it runs
[gofmt](https://pkg.go.dev/cmd/gofmt) in place, then surfaces a syntax
diagnostic back to Claude as advisory context when gofmt cannot parse the
file (common mid-edit).

It ships no rules of its own and runs unconditionally: gofmt has no
configuration surface — there is one canonical Go style — so there is no
consumer opt-in to discover or honor.

## Behavior

- **Runs on every `.go` edit, unconditionally.** gofmt needs no configuration
  to be useful; the hook never gates on any consumer config existing.
- **Extension-scoped.** Fires only on `*.go` files, like the sibling
  `ruff-format`/`bash-format` plugins.
- **Fix in place.** `gofmt -w` reformats the file. gofmt parses before it
  writes, so a syntax error (invalid Go, common mid-edit) leaves the file
  byte-for-byte untouched and reports the diagnostic instead — verified
  empirically against Go 1.26.5.
- **Advisory, never blocking.** The hook always exits `0`. A syntax diagnostic
  is reported via `additionalContext`; it never rejects the edit. Make a
  commit hook or CI your hard gate.

## Formatter choice

gofmt was chosen over goimports, gofumpt, and `golangci-lint fmt` for this
unconditional per-edit hook specifically:

- **goimports** removes unreferenced imports — the same hazard
  `ruff-format`'s `--unfixable F401` guard exists to prevent for Python, but
  Go imports have no per-tool "unfixable" escape hatch, so goimports would
  delete an import added one edit before the code that uses it.
- **gofumpt** ([mvdan.cc/gofumpt](https://github.com/mvdan/gofumpt)) is
  third-party and stricter than canonical `gofmt` style — an opinion this
  plugin does not impose unconditionally.
- **`golangci-lint fmt`** requires an explicit `formatters.enable` in the
  repo's own golangci-lint v2 config — verified empirically against
  golangci-lint v2.12.2 that it runs zero formatters with none, so it cannot
  serve as a zero-config unconditional default either.

A repo that wants import-organizing or stricter formatting configures it
through the `toolchain` plugin's batch `go` ecosystem entry
(`reference/ecosystems/go.yaml`), not this hook — see that file's `opt-in`
field.

## Known limitation

Claude Code runs every matching `PostToolUse` hook in parallel for one tool
call. This hook's `*.go` filter never overlaps another shipped format hook's
extension filter, so the cross-hook clobber race documented in
`typos-format`'s README (a language-agnostic hook racing an extension-scoped
one) does not apply here.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **gofmt** on `PATH`. It ships inside the Go toolchain's own bin directory
  alongside the `go` binary — never installed separately and never
  downloaded on the fly. If it is not present, the hook skips with a visible
  once-per-session notice. [Install Go](https://go.dev/dl/).

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

There are no formatting rules to configure — gofmt has none. One
`userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `go_format_enabled` | `true` | Kill switch — set `false` for a clean no-op. |

Set it interactively with `/plugin configure go-format`, or headless on the
install command:

```shell
claude plugin install go-format@melodic-software --config go_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the plugin off for a single repository, disable it in that project's
`enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
