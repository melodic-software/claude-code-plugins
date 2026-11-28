---
bump: patch
---

### Fixed

- `compress` now runs the repository's markdown lint command when a helper it calls is compiled or otherwise unreadable: an unreadable helper is not a write signal, and the copy plus the status and hash check around the run catch any write it makes.
- The `compress-lint-run-changes-target` eval case accepts a reply that reports the lint run modified or appended to `onboarding.md`, not only one that says it changed it.
