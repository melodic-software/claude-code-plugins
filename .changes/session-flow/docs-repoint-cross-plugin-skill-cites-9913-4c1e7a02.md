---
bump: patch
---

### Changed

- `audit-sessions`' `redact.py` is now a generated copy of the repository's shared `lib/redact.py`, which the corrections plugin also carries; the code is unchanged and it gains a generated-file header. The header changes the collector digest, so the next `collect` run re-ingests every transcript once.
