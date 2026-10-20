---
bump: minor
---

### Changed

- The `reference-verify` pre-push entry reads pushed files through the shared check library's `checks_file_text` and `checks_regular_file` instead of its own copies; what it reports is unchanged.
