# TypeScript LSP Windows npm .cmd shims

Park for
[#3537](https://github.com/melodic-software/claude-code-plugins/issues/3537).

## Decision

**Park. No unpaid shim.** TypeScript language-server launch on Windows via
npm `.cmd` shims stays a host/runtime concern until a maintainer funds a
design that does not weaken spawn policy.

- **Option A (taken):** park marketplace work on `.cmd` spawn.
- **Option B (declined):** ship a shelling shim or rewrite spawn rules unpaid.

**Claim:** this marketplace does not ship an unpaid TypeScript LSP Windows
`.cmd` spawn shim; fix belongs to host PATH / official plugin / Claude Code
runtime once funded.
**Basis:** #3537 (`work-class: scoped`, child of #3535). npm on Windows
installs `.cmd` shims; `CreateProcess` cannot run them without a shell
(Microsoft process-creation docs:
https://learn.microsoft.com/en-us/windows/win32/procthread/creating-processes).
Node's own Windows notes document `.cmd`/`.bat` requiring `shell: true` or
`cmd.exe` (https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).
Changing Claude Code or marketplace spawn policy is host-shaped and
security-adjacent; not a free drain patch. Ownership of LSP plugins stays
with `claude-plugins-official` per `ide-lsp-marketplace-ownership.md`.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds a spawn-safe design (native `node` entry,
official plugin fix, or documented host PATH layout) and unparks #3537.

## Revisit when

- Upstream/official plugin ships a Windows-safe entry, or
- A funded design is accepted here.

## Prior requests

- #3537 (2026-09-28): Option A park.
