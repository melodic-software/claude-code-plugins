---
bump: patch
---

### Changed

- Unattended loops hold to one GitHub API budget, now in the GitHub adapter reference (60 s background waits, GraphQL-only fields read once, writes one at a time, stop on the first rate-limit error); `tracker-seam.md`, work-loop's seam exit 8 handling and the triage lane point at it.
