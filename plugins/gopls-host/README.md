# gopls-host

A Claude Code plugin that proves the host `gopls` binary. It does not fork
`gopls` and it does not register a second language server. `gopls-lsp` from
the official marketplace remains the plugin that starts the server.

## Install

```shell
go install golang.org/x/tools/gopls@latest
/plugin install gopls-host@melodic-software
```

`go install` writes the executable to `GOBIN`, or to `GOPATH/bin` when
`GOBIN` is unset (`$HOME/go/bin` when `GOPATH` is also unset). That directory
has to be on `PATH` before Claude Code can start `gopls` by name. On Windows
the file is `gopls.exe`.

## Probe

`/gopls-host:probe` runs:

```shell
node "${CLAUDE_PLUGIN_ROOT}/skills/probe/scripts/gopls-smoke.mjs" --probe
node "${CLAUDE_PLUGIN_ROOT}/skills/probe/scripts/gopls-smoke.mjs" --lsp
```

`--probe` exits 0 when a native executable is on `PATH`. `--lsp` spawns that
absolute binary with `serve` and `shell` false, then checks hover, definition,
and references against a temporary module.

## Claim

`gopls` stays the official native Go language server. `go install` writes
`gopls` (Windows: `gopls.exe`) to `GOBIN`, or to `GOPATH/bin` when `GOBIN` is
unset. The smoke spawns that absolute executable with `shell` false and
`serve`, and checks hover, definition, and references. A `.cmd` shim is not
spawned, and this plugin does not fork `gopls`.

## Basis

- Install the latest stable server with `go install golang.org/x/tools/gopls@latest`:
  [go.dev/gopls](https://go.dev/gopls/).
- `GOBIN` is "The directory where 'go install' will install a command."
  Executables are installed in `GOBIN`, which defaults to `$GOPATH/bin` or
  `$HOME/go/bin` when `GOPATH` is unset:
  [go command environment](https://pkg.go.dev/cmd/go#hdr-Environment_variables)
  and the `go install` paragraph on that page.
- Claude Code's Go binary is `gopls`:
  [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence).
- The manifest example starts `gopls` with `args` `serve`:
  [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference).
- `CreateProcessW` appends `.exe` and cannot run a batch file without
  `cmd.exe`:
  [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).

## As of

2026-09-28. gopls v0.21.1 help text says a bare invocation defaults to `serve`;
the smoke passes `serve` explicitly so it does not depend on that default.
The pages above were fetched the same day.

## Recheck

When `go install` stops documenting `GOBIN` and `$GOPATH/bin`, when
`gopls help` drops the `serve` command, or when the code intelligence table
stops naming `gopls`.

## License

MIT (SPDX-License-Identifier: MIT).
