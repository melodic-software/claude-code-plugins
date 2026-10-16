---
bump: patch
---

### Fixed

- `block-hook-bypass` block message: an agent with neither Write nor Edit (for example a read-only verifier) is told to write to an unquoted literal path under an exempt root, and the python lane names the roots a script file can be written under and run from with `python3 <file>`.
