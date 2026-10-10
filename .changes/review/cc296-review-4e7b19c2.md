---
bump: patch
---

### Fixed

- **`/review:quality-gate` code mode no longer misdescribes the bundled `/code-review` effort levels.** The boundary section claimed which levels report only the most confident findings, which Claude Code 2.1.290 made untrue. It now states our routing rule instead (choose between this mode and `/code-review` by what the review must ground in and whether it may write, never by effort level), routes convention review to this mode even when `/code-review` reports convention findings, and points at the code-review page's effort section for the current per-level behavior.
