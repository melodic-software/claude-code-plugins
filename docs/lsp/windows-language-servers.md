# Windows language servers

Status for epic [#3535](https://github.com/melodic-software/claude-code-plugins/issues/3535).
This page points at the child branches. It does not close the epic. The child
plugins are not in this branch.

## Rule

Prefer a language server that is installed as a native executable. Use a
launcher only when the server is an npm JavaScript `bin`, because that `bin`
is a `.cmd` file on Windows and Claude Code starts an LSP `command` with no
shell.

## Children

| Issue | Branch | Commit | What it ships |
| --- | --- | --- | --- |
| [#3537](https://github.com/melodic-software/claude-code-plugins/issues/3537) | `cursor/3537-ts-lsp-launcher-37e9` | `15846b70ec2e8f18ca9b4dd9ccbf77306a29dab0` | `plugins/typescript-lsp`: `node` plus `lib/cli.mjs`, with `cmd.exe /d /s /c` only if that entry is missing |
| [#3536](https://github.com/melodic-software/claude-code-plugins/issues/3536) | `cursor/3536-csharp-lsp-windows-37e9` | `e461c3f72ee9bab1315f36d62cb4cf549e09abf8` | `plugins/csharp-lsp`: native `csharp-ls` apphost, `DOTNET_ROOT` set from the `dotnet` host |
| [#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539) | `cursor/3539-gopls-native-probe-37e9` | `8926ee2ec881ee74d435797fe3ff9c79d06dd649` | `plugins/gopls-lsp`: `command` is `gopls`, plus `scripts/probe-gopls.mjs` |

[#3538](https://github.com/melodic-software/claude-code-plugins/issues/3538)
(Python) is already closed. Pyright stays the uv native executable. This page
does not reopen it.

The commits above were cut from `origin/main` `ec232d017`. Each child README
holds the four-part record for its server choice and spawn plan.

## Still open

Merging the child branches is still required before this marketplace installs
the plugins. After that, an operator on Windows confirms the LSP tool in
Claude Code: a TypeScript file, a multi-project C# solution, and a Go module.
Cloud sessions do not start plugin language servers, so that check is not a
CI result.

## Verification

**Claim:** TypeScript is the npm `.cmd` case and starts through `node` and
`lib/cli.mjs`. C# starts as the `csharp-ls` apphost once `DOTNET_ROOT` is set
from the `dotnet` host. Go starts as native `gopls` with no wrapper, and the
probe accepts only an ELF, PE, or Mach-O file that answers LSP `initialize`.

**Basis:** The child READMEs on the commits in the table, which cite the
typescript-language-server README, npm `bin`, Node.js child process, and
`CreateProcessW` (TypeScript); the csharp-ls README, the NuGet version index,
and `DOTNET_ROOT` (C#); and go.dev/gopls, gopls' default `serve` command, and
the official `gopls-lsp` manifest (Go). Claude Code's plugin reference names
LSP `command` as the binary and substitutes `${CLAUDE_PLUGIN_ROOT}` in LSP
`args` (<https://code.claude.com/docs/en/plugins-reference>, fetched
2026-09-28).

**As of:** 2026-09-28

**Recheck:** a child recheck trigger firing, or a merge of one of those
branches that changes the plugin path or the spawn command.
