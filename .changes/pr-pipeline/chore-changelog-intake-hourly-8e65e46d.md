---
bump: patch
---

### Changed

- The release intake lane (`upstream-apply-changelog.yml`) runs hourly, at minute 25, where it ran every ten minutes. No event reaches this repository when a Claude Code release ships, and about one release a day came in; the env-scrub probe of each release runs up to an hour after it ships.
