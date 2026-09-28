# Windows LSP epic

Recorded park for
[#3535](https://github.com/melodic-software/claude-code-plugins/issues/3535)
(EPIC: make Claude Code language servers work on Windows).

## Decision

**Park the unpaid epic.** This marketplace does not own a Windows LSP program.
Children #3536 and #3539 are declined on the ownership ledger. #3537
(TypeScript `.cmd` shims) has its own park.

- **Option A (taken):** close the epic as parked marketplace-side; remaining
  host/shim work is not a drain implement.
- **Option B (declined):** implement a marketplace Windows LSP vertical now.

**Claim:** epic #3535 stays parked; marketplace ownership of IDE language
servers is declined; TypeScript `.cmd` spawn is a separate host-shaped park.
**Basis:** #3535 rewrite 2026-09-01 after Windows measurement. Ownership ledger
`ide-lsp-marketplace-ownership.md` (PR for #3536/#3539). Official Claude Code
plugins surface is skills/agents/hooks/MCP
(https://code.claude.com/docs/en/plugins), not shipping language servers.
Official marketplace language-server plugins live under
`claude-plugins-official` (https://code.claude.com/docs/en/discover-plugins).
**As of:** 2026-09-28.
**Recheck:** a maintainer funds marketplace ownership of a named language
server, or unparks #3535 after #3537 is resolved on the host.

## Children

| Issue | Status of this park |
|---|---|
| #3536 C# | declined on ownership ledger |
| #3539 Go control case | declined on ownership ledger |
| #3537 TypeScript `.cmd` | see `typescript-lsp-windows-cmd-shim.md` |

## Revisit when

- A maintainer funds marketplace LSP ownership, or
- #3537 is unparked with a funded host/shim design.

## Prior requests

- #3535 (2026-09-28): Option A park.
