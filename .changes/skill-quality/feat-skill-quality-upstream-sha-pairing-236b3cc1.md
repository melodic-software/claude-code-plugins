---
bump: minor
---

### Added

- Check 8 also accepts a `vendor/` change paired with a `metadata.upstream-sha` bump that equals the content hash it recomputes offline (SHA-256 of the single vendored non-dotfile with CR removed, or of the sorted per-file hash lines for several files), so a resync whose upstream changed bytes without a version bump passes. A sha that does not match fails, naming both hashes.
