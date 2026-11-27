---
bump: patch
---

### Changed

- The shared redactor copy (`redact.py`) gains a published-output redactor for fleet identifiers; this plugin's own redaction is unchanged.
- The shared redactor copy (`redact.py`) can leave report field names its caller lists unredacted; this plugin lists none, so its redaction is unchanged.

### Fixed

- Redacting a secret at the end of a line no longer joins the next line onto the redacted one.
