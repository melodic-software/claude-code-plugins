---
bump: patch
---

### Fixed

- Shared interview: pressing Run or Run all shown on the request queue shows the started requests as running at once and hides Run all while nothing waits; a refused run puts them back and says why. A single Run works again: it was sent without the ids the session needs.
