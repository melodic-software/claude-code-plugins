---
bump: minor
---

### Added

- **`check-security-binding.mjs --evidence -` reads the events from stdin**, so a caller that
  computed them need not write a file. Every evaluation-mode fixture now also runs through stdin
  and must print the same verdict.
