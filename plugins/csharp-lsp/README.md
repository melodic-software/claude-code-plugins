# csharp-lsp

A Claude Code language server for C# that starts `csharp-ls`, the native
apphost installed by `dotnet tool`. On Windows that file is `csharp-ls.exe`.
Claude Code spawns language servers with no shell and no profile, so two
launch gaps show up as a silent server: the tools directory is not on PATH,
or `DOTNET_ROOT` is unset and the apphost exits before it writes any LSP
bytes.

## Server choice

This plugin starts **csharp-ls**, at least 0.24.0 (the current NuGet index
runs through 0.28.0). It does not start Roslyn's language server or OmniSharp.

`csharp-ls` is the server `csharp-lsp@claude-plugins-official` already names,
it installs as a native executable, and it speaks LSP on stdio with no extra
flag. The launcher's job is the Windows process environment, not a protocol
proxy.

Rejected for this plugin:

- `roslyn-language-server`. The NuGet version index fetched with this record
  contains only prerelease versions (the newest entry is `5.12.0-1.26426.8`).
  It is a larger install and a second spawn contract. It stays a later option
  if a stable package documents a native Windows executable.
- OmniSharp. Tag `v2.0.0` was published on 2026-09-18, so "unmaintained" is
  not the reason. The official Claude Code C# plugin and this one start
  `csharp-ls`, not OmniSharp.
- A proxy that answers `client/registerCapability`,
  `workspace/configuration`, and `window/workDoneProgress/create`. That shim
  targets a client mismatch reported against csharp-ls 0.16.0. Releases from
  0.24.0 upward are the floor this plugin documents. The launcher does not
  invent those responses.

## Install

Install the .NET 10 SDK or later, then the global tool:

```sh
dotnet tool install --global csharp-ls
```

The tool lands in `~/.dotnet/tools` (`%USERPROFILE%\.dotnet\tools\csharp-ls.exe`
on Windows). Enable `csharp-lsp@melodic-software`. Disable
`csharp-lsp@claude-plugins-official` in the same session so two servers do not
claim `.cs`.

This section is the only operator install step.

## How it starts

`.lsp.json` sets `command` to `node` and `args` to the bundled launcher.
`${CLAUDE_PLUGIN_ROOT}` is substituted before the process starts. The launcher
resolves `csharp-ls.exe` or `csharp-ls` from `CSHARPLS_PATH`, then PATH, then
the dotnet tools directory. A `.cmd` or `.bat` hit is ignored.

When `DOTNET_ROOT` is unset, the launcher sets it to the directory that
contains `dotnet` or `dotnet.exe`. On Windows x64 it also sets
`DOTNET_ROOT_X64` when that variable is unset. Values already present are left
alone. The apphost is spawned with `shell: false`.

## Verification

**Claim:** The Windows C# server to start is the `csharp-ls` dotnet tool, a
native apphost. An apphost finds runtimes through `DOTNET_ROOT` when they are
not in the default location, and that variable is consulted only for generated
executables. This plugin spawns that apphost and sets `DOTNET_ROOT` from the
`dotnet` host when the variable is empty.

**Basis:** csharp-ls requires the .NET 10 SDK and installs with
`dotnet tool install --global csharp-ls`
(<https://github.com/razzmatazz/csharp-language-server/blob/main/README.md>,
fetched 2026-09-28). The NuGet version index
<https://api.nuget.org/v3-flatcontainer/csharp-ls/index.json> lists `0.24.0`
through `0.28.0`. `DOTNET_ROOT` "specifies the location of the .NET runtimes,
if they are not installed in the default location" and "these environment
variables are used only when running apps via generated executables
(apphosts)"
(<https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables#dotnet_root-dotnet_rootx86-dotnet_root_x86-dotnet_root_x64>,
fetched 2026-09-28). `roslyn-language-server` versions fetched the same day
from <https://api.nuget.org/v3-flatcontainer/roslyn-language-server/index.json>
are prerelease only, newest `5.12.0-1.26426.8`. OmniSharp tag `v2.0.0` is
dated 2026-09-18
(<https://github.com/OmniSharp/omnisharp-roslyn/releases/tag/v2.0.0>).

**As of:** 2026-09-28

**Recheck:** a csharp-ls release that stops shipping a `dotnet tool` apphost,
a .NET host change that stops reading `DOTNET_ROOT` for apphosts, or a stable
(non-prerelease) `roslyn-language-server` whose install docs name a native
Windows executable this plugin should start instead.

## Operator check

On a Windows desktop, open a `.cs` file in a multi-project solution and
confirm the LSP tool answers document symbols, hover, go-to-definition, and
find-references. The tests here prove the spawn plan and a stdio handshake
against a stand-in apphost. They do not open Claude Code's UI, and this
container has no .NET SDK, so they do not load a real solution.
