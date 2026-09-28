# csharp-ls-windows

A Claude Code plugin that starts the [csharp-ls](https://www.nuget.org/packages/csharp-ls)
dotnet global tool for `.cs` files. The server stays `csharp-ls`. The Windows
failure mode this plugin closes is `PATH` and `DOTNET_ROOT`, not a `.cmd` shim
and not a switch to another language server.

## Install

```shell
dotnet tool install --global csharp-ls
/plugin install csharp-ls-windows@melodic-software
```

On Windows, `%USERPROFILE%\.dotnet\tools` must be on the `PATH` of the shell
that starts Claude Code. That is the default global-tools directory from
[.NET global tools](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools).

## Spawn

`.lsp.json` runs `node` on `bin/csharp-ls-windows-spawn.mjs`. The script
resolves `csharp-ls.exe` from `PATH`, spawns that absolute path with `shell`
false, and sets `DOTNET_ROOT` to the directory of `dotnet.exe` when
`DOTNET_ROOT` is unset. A `csharp-ls.cmd` on `PATH` is recorded and not
started.

`/csharp-ls-windows:probe` prints the same plan as JSON and does not start the
server.

## Claim

The Windows spawn target stays the `csharp-ls` dotnet global tool. When `PATH`
already contains `csharp-ls.exe`, this plugin spawns that absolute executable
with `shell` false and sets `DOTNET_ROOT` from the `dotnet` host when the
variable is unset. It does not spawn `csharp-ls.cmd` and it does not switch the
server to the Roslyn language-server CLI.

## Basis

- Claude Code names the C# binary `csharp-ls`:
  [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence).
- Install with `dotnet tool install --global csharp-ls`. Windows tools land in
  `%USERPROFILE%\.dotnet\tools`:
  [NuGet csharp-ls](https://www.nuget.org/packages/csharp-ls) and
  [.NET global tools](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools).
- `DOTNET_ROOT` locates the runtime for an apphost when it is not in the default
  location (`C:\Program Files\dotnet` on Windows):
  [DOTNET_ROOT](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables#dotnet_root-dotnet_rootx86-dotnet_root_x86-dotnet_root_x64).
- LSP `command` and `args` substitute `${CLAUDE_PLUGIN_ROOT}`:
  [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference).
- `CreateProcessW` appends `.exe` and cannot run a batch file without
  `cmd.exe`:
  [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).
- Node.js refuses a shell-less `.cmd` launch (`execFile`; `spawn` with `shell`
  is DEP0190):
  [Spawning .bat and .cmd files on Windows](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).

## As of

2026-09-28. NuGet `csharp-ls` 0.28.0. The Claude Code pages above were fetched
the same day.

## Recheck

When the code intelligence table stops naming `csharp-ls`, when the NuGet
`csharp-ls` page stops documenting `dotnet tool install --global csharp-ls`,
when the `DOTNET_ROOT` section changes the default Windows runtime directory,
or when the Node child_process page gains a shell-less way to launch `.cmd`.

## License

MIT (SPDX-License-Identifier: MIT).
