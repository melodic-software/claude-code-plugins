---
bump: patch
---

### Changed

- `/work-items:work`: the issue lane's outcome file takes three more stop codes: `blocked-by-pr` (waits on an open pull request, run again once it merges or closes), `already-done` (work already on the default branch, closed once the lane confirms the cited commit or pull request) and `report-delivered` (a read-only issue's report, posted and closed). A reason with no code is run once more and then stops, rather than going to a person.
