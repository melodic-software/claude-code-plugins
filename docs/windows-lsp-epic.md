# Windows language-server epic

Status index for
[#3535](https://github.com/melodic-software/claude-code-plugins/issues/3535).
The epic is in progress as three child deliverables. This page records the
spawn contracts. It does not park the work, and it does not vendor a language
server.

## Claim

Claude Code language servers on Windows stay on the official binaries: C#
`csharp-ls`, TypeScript `typescript-language-server`, and Go `gopls`. C# is a
dotnet global tool (`csharp-ls.exe`) with `PATH` and `DOTNET_ROOT`. TypeScript
starts as `node.exe` plus `lib/cli.mjs --stdio`, or as a real executable of
that name, never as an npm `.cmd`. Go is the native `gopls.exe` from
`go install`, on `PATH` via `GOBIN` or `GOPATH/bin`. Python (#3538) is already
closed on a native executable.

## Basis

- The code intelligence table names those binaries (`csharp-ls`,
  `typescript-language-server`, `gopls`, `pyright-langserver`):
  [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence).
- C# install and the Windows tools directory:
  [NuGet csharp-ls](https://www.nuget.org/packages/csharp-ls),
  [.NET global tools](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools),
  [DOTNET_ROOT](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables#dotnet_root-dotnet_rootx86-dotnet_root_x86-dotnet_root_x64).
- TypeScript's npm `bin` is `lib/cli.mjs` (package `typescript-language-server`
  6.0.1, registry fetched 2026-09-28). On Windows a package `bin` is a `.cmd`:
  [package.json bin](https://docs.npmjs.com/cli/v11/configuring-npm/package-json#bin).
  Node cannot launch a `.cmd` without a shell (DEP0190):
  [Spawning .bat and .cmd files on Windows](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).
- Go install location is `GOBIN`, else `GOPATH/bin`:
  [go.dev/gopls](https://go.dev/gopls/),
  [go command environment](https://pkg.go.dev/cmd/go#hdr-Environment_variables).
- `CreateProcessW` appends `.exe` and runs a batch file only through `cmd.exe`:
  [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).

## As of

2026-09-28.

## Recheck

When the code intelligence table renames a binary, when Node documents a
shell-less `.cmd` launch, or when `go install` stops placing commands in
`GOBIN` / `GOPATH/bin`.

## Children

| Issue | Deliverable | Spawn contract |
| --- | --- | --- |
| [#3536](https://github.com/melodic-software/claude-code-plugins/issues/3536) | `plugins/csharp-ls-windows` | Absolute `csharp-ls.exe` from `PATH`. `DOTNET_ROOT` from the environment or the `dotnet` host. No `.cmd`. |
| [#3537](https://github.com/melodic-software/claude-code-plugins/issues/3537) | `plugins/typescript-lsp-stdio` | `node.exe` plus `lib/cli.mjs --stdio`, or a real `typescript-language-server` executable. No `.cmd`. No `shell`. |
| [#3538](https://github.com/melodic-software/claude-code-plugins/issues/3538) | Closed | `pyright-langserver` is already a native executable. |
| [#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539) | `plugins/gopls-host` | Native `gopls` / `gopls.exe`. Smoke hover, definition, and references. `PATH` must include `GOBIN` or `GOPATH/bin`. No fork. |

The child directories land with their own changes. This page is the index
that links them.

## What stays out of this repository

- The language server sources. Each host installs `csharp-ls`,
  `typescript-language-server`, and `gopls`.
- A `.cmd` launcher and `shell: true`.
- A switch from `csharp-ls` to the Roslyn language-server CLI.
