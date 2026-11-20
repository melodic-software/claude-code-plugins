---
bump: patch
---

### Changed

- pr-verify no longer fails a `Refs:` pull request whose body names no remaining work. It still fails one whose body names no delivered part, claims the whole issue, or delivers a part outside the issue's scope. What stays open is the issue's own done-when list, so the body need not restate it.
