---
description: "Report whether gopls is a native executable on PATH and whether that directory is GOBIN, then smoke hover, definition, and references. Read-only, performs zero mutations. Use when: 'gopls not on PATH', 'GOBIN', 'Go language server on Windows'."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report gopls PATH and GOBIN and smoke hover definition references
---

## Purpose

Prove the host `gopls` binary. This plugin does not fork `gopls` and does not
ship a second `.lsp.json`. Claude Code's Go plugin already runs `gopls`. The
work here is to show the binary is a native executable and that `PATH` contains
the `go install` directory.

Run the path report:

```shell
node "${CLAUDE_PLUGIN_ROOT}/skills/probe/scripts/gopls-smoke.mjs" --probe
```

Exit 0 means a native `gopls` is on `PATH`. Exit 2 means it is not. Then, when
`binary` is set, run the protocol smoke even if `onPath` is false:

```shell
node "${CLAUDE_PLUGIN_ROOT}/skills/probe/scripts/gopls-smoke.mjs" --lsp
```

Exit 0 means hover, definition, and references each returned a result. The
smoke uses a temporary module. It does not edit the consumer repository.

## How to read the report

- `shell` is `false`. `args` is `serve` when a native binary is on `PATH`.
- `command` is the absolute `gopls.exe` on Windows, or the absolute `gopls`
  elsewhere. It is never a `.cmd`.
- `binary` is that executable, including when it was found only in the install
  directory and is not on `PATH` yet.
- `installDir` is `GOBIN` when `GOBIN` is set, otherwise the first `GOPATH`
  entry's `bin` directory, otherwise `$HOME/go/bin` (on Windows,
  `%USERPROFILE%/go/bin`).
- `installOnPath` says whether `installDir` is on `PATH`.
- `lsp.hover`, `lsp.definition`, and `lsp.references` are the smoke results.

When `status` is `blocked` because the install directory is off `PATH`, report
the directory and the install command. Do not edit the user profile.

```shell
go install golang.org/x/tools/gopls@latest
```

Put `GOBIN`, or `GOPATH/bin` when `GOBIN` is unset, on `PATH`, then start a
new session.

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

## Gotchas

- `GOBIN` empty means the install directory is `GOPATH/bin`, not a directory
  named `GOBIN`. Read `go env GOBIN` and `go env GOPATH`.
- A `gopls.cmd` on `PATH` is rejected. The smoke spawns the native file by
  absolute path.
- `--lsp` can succeed while `--probe` exits 2. That means the binary works
  and the install directory is still missing from `PATH`.
- The smoke module is disposable. Nothing in the consumer repository is
  modified.
