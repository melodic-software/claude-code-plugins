---
bump: minor
---

### Changed

- Issue-lane admission, work-resolve-issue's blocker check and the work-unblock sweep count a blocker the lanes App closed as resolved when the App's own `work-resolve-issue outcome=closed` comment marks that close, so a dependent of a `report-delivered` blocker admits without a re-triage (owner Q300). The comment must be the lanes App's and postdate the issue's last reopen, and an `already-done` or `verified-done` close still counts only while its evidence re-checks true (owner Q9). An App close without that comment, a close comment someone else wrote, or a read that fails still counts for nothing.
