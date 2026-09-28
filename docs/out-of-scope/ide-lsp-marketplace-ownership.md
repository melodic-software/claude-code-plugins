# IDE language-server marketplace ownership

Recorded decline for
[#3536](https://github.com/melodic-software/claude-code-plugins/issues/3536)
and
[#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539).
Child issues of
[#3535](https://github.com/melodic-software/claude-code-plugins/issues/3535).

## Decision

**Park. Do not own.** This marketplace does not ship, shim, or maintain IDE
language-server plugins.

- **Option A (taken):** decline marketplace ownership of IDE LSP servers.
  C# and Go stay on the official plugins plus host provisioning
  (`csharp-lsp@claude-plugins-official`, `gopls-lsp@claude-plugins-official`).
- **Option B (declined):** pick a C# server and ship a proxying shim.
- **Option C (declined):** treat Go as a control case that this repo must
  re-measure and document as a marketplace deliverable.

**Claim:** this marketplace does not own IDE language servers; C# and Go stay
with the official plugins and host PATH. Remaining work is operator-desktop
confirmation, not a plugin.
**Basis:** #3535 rewritten 2026-09-01 after the Windows measurement pass.
Measured: Go `gopls.exe` native stable works (#3539); C# `csharp-ls.exe` via
dotnet tool native stable works (#3536); csharp-ls 0.27.0 needs no three-handler
shim (claude-plugins-official#1359 was against 0.16.0.0; fixes in 0.22.0 and
0.24.0). #3536 and #3539 both carry `needs-human`. Neither language has an
LSP skill under `plugins/`. #3537 (TypeScript npm `.cmd` spawn) is the
remaining engineering on the parent and is not declined here.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds marketplace ownership of a named language
server, or Claude Code cloud sessions start language servers and this
marketplace is asked to ship one.

## Rationale

- The epic's own rewrite closed the original "own and shim all of them"
  framing. Three of four languages work untouched.
- A csharp-ls shim would guard requests the current server no longer needs.
- Go was the control case: native binary, stock plugin, no fork. Confirming
  it again is host PATH work, not a marketplace file.
- Both issues are `needs-human`. Behavioral confirmation needs an attended
  desktop.

## Revisit when

- A maintainer names a language server this marketplace will own, or
- #3535's TypeScript remaining work changes the ownership rule.

## Prior requests

- #3536 (2026-09-28): C# LSP; Option A.
- #3539 (2026-09-28): Go LSP control case; Option A.
