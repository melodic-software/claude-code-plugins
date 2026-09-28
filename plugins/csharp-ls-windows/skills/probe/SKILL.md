---
description: "Report whether csharp-ls resolves to a native executable and whether DOTNET_ROOT is set. Read-only, performs zero mutations. Use when: 'csharp-ls not found on Windows', 'C# language server will not start', 'DOTNET_ROOT', 'dotnet global tools PATH'."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report csharp-ls PATH and DOTNET_ROOT spawn readiness
---

## Purpose

Report the spawn plan for `csharp-ls` and stop. The plugin keeps the
[csharp-ls](https://www.nuget.org/packages/csharp-ls) dotnet global tool. It does
not retarget C# at another language server.

Run:

```shell
node "${CLAUDE_PLUGIN_ROOT}/bin/csharp-ls-windows-spawn.mjs" --probe
```

Exit 0 means `status` is `ready`. Exit 2 means `blocked`. Read the JSON. Do not
start the server from this skill: without `--probe` the process stdout is the
language-server stream.

## How to read the report

- `shell` is `false`. A `true` value is a defect.
- `command` is an absolute `csharp-ls.exe` on Windows, or the absolute `csharp-ls`
  binary on Unix. It is never a `.cmd`, `.bat`, or `.ps1` path.
- `rejected` lists shim paths that were seen and not spawned.
- `toolsDir` is `%USERPROFILE%\.dotnet\tools` on Windows and `$HOME/.dotnet/tools`
  elsewhere. `toolsDirOnPath` says whether that directory is already on `PATH`.
- `dotnetRoot` is the value the child process will see. `dotnetRootSource` is
  `env` when `DOTNET_ROOT` was already set, `dotnet-host` when it was taken from
  the directory of `dotnet.exe` (or `dotnet`), and `unset` when neither is available.

When `status` is `blocked`, report `reason` and the host commands below. Do not
edit the user profile, the shell rc, or the system `PATH`.

```shell
dotnet tool install --global csharp-ls
```

On Windows, add `%USERPROFILE%\.dotnet\tools` to the user `PATH`, then start a
new session from a shell that has it. Set `DOTNET_ROOT` only when the report
says `dotnetRootSource` is `unset` and `csharp-ls.exe` then fails to find the
runtime. `DOTNET_ROOT` is the directory that contains `dotnet.exe`, not the
tools directory.

## Claim

The Windows spawn target stays the `csharp-ls` dotnet global tool. When `PATH`
already contains `csharp-ls.exe`, this plugin spawns that absolute executable
with `shell` false and sets `DOTNET_ROOT` from the `dotnet` host when the
variable is unset. It does not spawn `csharp-ls.cmd` and it does not switch the
server to the Roslyn language-server CLI.

## Basis

- Claude Code names the C# binary `csharp-ls`:
  [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence).
- `csharp-ls` is installed with `dotnet tool install --global csharp-ls`. The
  default Windows tools directory is `%USERPROFILE%\.dotnet\tools`:
  [NuGet csharp-ls](https://www.nuget.org/packages/csharp-ls) and
  [.NET global tools](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools).
- `DOTNET_ROOT` is the runtime location used by apphost executables when the
  runtime is not in the default location. The default Windows location is
  `C:\Program Files\dotnet`:
  [DOTNET_ROOT](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables#dotnet_root-dotnet_rootx86-dotnet_root_x86-dotnet_root_x64).
- LSP `command`, `args`, and `env` substitute `${CLAUDE_PLUGIN_ROOT}`:
  [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference).
- `CreateProcessW` appends `.exe` when the name has no extension, and a batch
  file has to be started through `cmd.exe`:
  [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).
- Node.js cannot launch a `.cmd` with `execFile`. `spawn` with `shell` set is
  not recommended (DEP0190):
  [Spawning .bat and .cmd files on Windows](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).

## As of

2026-09-28. NuGet `csharp-ls` 0.28.0. Claude Code plugin manifest reference and
code intelligence page fetched the same day.

## Recheck

When the code intelligence table stops naming `csharp-ls`, when the NuGet
`csharp-ls` page stops documenting `dotnet tool install --global csharp-ls`,
when the `DOTNET_ROOT` section changes the default Windows runtime directory,
or when the Node child_process page gains a shell-less way to launch `.cmd`.

## Gotchas

- Bare `spawn("csharp-ls")` on Windows can resolve `csharp-ls.cmd` through
  `PATHEXT`. The adapter spawns the absolute `.exe` so the shim is not selected.
- `DOTNET_ROOT` is not the tools directory. Pointing it at `.dotnet\tools`
  makes the apphost look for the runtime in the wrong place.
- The adapter does not search outside `PATH`. A tools directory that is missing
  from `PATH` stays `blocked` until the operator adds it.
- Installing both this plugin and `csharp-lsp@claude-plugins-official` attaches
  two servers to `.cs` files. Use one of them.
