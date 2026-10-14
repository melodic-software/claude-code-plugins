---
bump: patch
---

### Changed

- `scripts/transcript_reader.py` is now a generated copy of the repository canonical `lib/transcript_reader.py`; its imports and behavior are unchanged. The added generated-file header changes the file's bytes, so audit-sessions' collector digest changes once and the next collect re-ingests every transcript in full.
