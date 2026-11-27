---
bump: patch
---

### Changed

- The shared redactor copy (`redact.py`) gains a published-output redactor for fleet identifiers; this plugin's own redaction is unchanged.
- `/corrections:codify preferences` counts the prompts the session store kept from sessions whose transcript is gone, and quotes excerpts only as `/session-flow:audit-sessions` returns them, already through the publish redactor.
- The shared redactor copy (`redact.py`) can leave report field names its caller lists unredacted; this plugin lists none, so its redaction is unchanged.

### Fixed

- Redacting a secret at the end of a line no longer joins the next line onto the redacted one.
- A secret whose gitleaks rule marks only part of it, such as a base64 JWT, a Teams webhook URL or a Kubernetes Secret's later data values, is redacted whole; only line breaks and a trailing quote, space or semicolon are kept.
