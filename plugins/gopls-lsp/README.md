# gopls-lsp

The Go control case for Windows language servers. `go install
golang.org/x/tools/gopls@latest` produces a native executable (`gopls.exe` on
Windows, an ELF or Mach-O binary elsewhere). Claude Code can spawn that file
with no shell. This plugin records that packaging and ships a probe that
checks it.

## Install

```sh
go install golang.org/x/tools/gopls@latest
```

`gopls` must be on PATH for a non-login process. The usual directory is
`$(go env GOPATH)/bin` or `GOBIN`. Enable `gopls-lsp@melodic-software`, or
keep `gopls-lsp@claude-plugins-official`. Both use the same command. Do not
enable both in one session.

## Packaging

`.lsp.json` sets `command` to `gopls` and does not set `args`. When no
subcommand is given, gopls runs `serve`, which is the language server. There
is no `.cmd` shim and no `node` wrapper. That is the packaging. A script
named `gopls` would be the broken shape this probe rejects.

## Probe

```sh
node plugins/gopls-lsp/scripts/probe-gopls.mjs
```

The probe resolves `gopls` (`GOPLS_PATH`, then PATH, `GOBIN`, `GOPATH/bin`,
and `~/go/bin`), reads the file header, and exits 1 unless the header is ELF,
PE, or Mach-O. It then spawns that file with `shell: false` and no arguments,
sends LSP `initialize` on stdin, and exits 0 only when the result carries
`capabilities`. Exit 2 means the binary is not installed.

`--command /path/to/gopls` probes one file instead of searching PATH.

## Verification

**Claim:** gopls is the native-executable control case. `go install
golang.org/x/tools/gopls@latest` builds a real binary, and with no
subcommand that binary serves LSP on stdio. A shell script or npm `.cmd`
is not a valid gopls package for Claude Code.

**Basis:** The install command is `go install golang.org/x/tools/gopls@latest`
(<https://go.dev/gopls/>, fetched 2026-09-28). gopls help text says "When no
command is specified, gopls will default to the 'serve' command"
(<https://raw.githubusercontent.com/golang/tools/master/gopls/internal/cmd/cmd.go>,
fetched 2026-09-28). The official marketplace entry uses `"command": "gopls"`
with no args
(<https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json>,
fetched 2026-09-28). Claude Code's plugin reference names `command` as the
language server binary and shows the same `gopls` command
(<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-09-28).

**As of:** 2026-09-28

**Recheck:** a gopls release whose default command is no longer `serve`, or
whose install docs stop producing a native executable, or a Claude Code
release that spawns language servers through a shell.

## Operator check

On Windows, `where.exe gopls` should end in `gopls.exe`. Run the probe there.
Opening a `.go` file in Claude Code and asking for hover is still a separate
UI check. The probe is the spawn check.
