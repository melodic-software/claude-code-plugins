---
bump: patch
---

### Changed

- The shared redactor copy (`redact.py`) gains a published-output redactor for fleet identifiers; this plugin's own redaction is unchanged.
- `/corrections:codify preferences` counts the prompts the session store kept from sessions whose transcript is gone, and quotes excerpts only as `/session-flow:audit-sessions` returns them, already through the publish redactor.
