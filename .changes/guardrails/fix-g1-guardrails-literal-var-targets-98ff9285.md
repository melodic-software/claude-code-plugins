---
bump: patch
---

### Fixed

- `block-hook-bypass` block message: an agent with neither Write nor Edit (for example a read-only verifier) is told to write to a literal path under an exempt root, unquoted or, on PowerShell, single-quoted.
