---
bump: patch
---

### Changed

- pr-verify names each verdict artifact `pr-verify-<pr>-<head-sha>-<verdict>-<ref-digest>`, the digest being the first 16 hex digits of the SHA-256 of the head branch the verdict records. The pr-merge gate ties an untied FAIL to a pull request from that name without downloading it; the resolver, the FAIL-notes poster (`verify-notes.mjs`, which also checks the digest against the verdict) and pr-feedback-dispatch accept both the new name and the old one, which artifacts uploaded before this change keep until they expire.
