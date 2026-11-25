---
bump: minor
---

### Changed

- Issue-lane admission, work-resolve-issue's blocker check and the work-unblock sweep count a blocker the lanes App closed as resolved when the App's own `work-resolve-issue outcome=closed` comment marks that close, whatever its stop, so a dependent of a `report-delivered` blocker admits without a re-triage (owner Q300). The comment must be the lanes App's and postdate the issue's last reopen; an App close without one, a close comment someone else wrote, or a read that fails still counts for nothing. An `already-done` or `verified-done` close's evidence is no longer re-checked at read time: report-outcome checks it before it closes.
