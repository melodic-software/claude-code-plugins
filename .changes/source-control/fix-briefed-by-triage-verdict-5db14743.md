---
bump: minor
---

### Changed

- The babysit merge gate also trusts an issue the lanes App filed whose intake-triage verdict comment, posted and last edited by the lanes App's account id, holds nothing because the issue is ready or admission moved it, and stamps the issue's current title and body by sha256 (`triage_briefed`), with the same veto set as the admission-record rule, matching pr-verify's `briefedIssue`.
