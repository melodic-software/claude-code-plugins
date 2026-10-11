---
bump: minor
---

### Added

- `/discovery:research` documents how to date a living vendor page that prints no date: `published:` records a date the publisher or its source repository attaches to the content, never a serve-time header, and a per-family method table covers code.claude.com, docs.github.com and Microsoft Learn. A source entry may carry `dated_by:` naming the method, `check-source-applicability.py` rejects a `dated_by:` that names a serve-time header, and `research-verifier` grades the recorded method instead of choosing its own.
