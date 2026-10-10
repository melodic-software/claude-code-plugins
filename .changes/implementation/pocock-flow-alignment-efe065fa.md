---
bump: minor
---

### Changed

- `/implementation:implement` keys skipping the plan on the diff being quick to review and cheap to retry, not on file count, and routes back to the interview when the diff turns out not to be quick to review. A too-big, foggy effort found mid-build now routes to `/planning:interview`, which escalates to `/planning:wayfind`.
