---
bump: patch
---

### Fixed

- pr-merge's `gate-check` job writes a `pr-merge / gate` check only at a candidate's current pull request head: its read also fetches each pull request's head, and a row whose head differs, or whose pull request the read reports `NOT_FOUND`, is skipped with a logged reason instead of taking its commit from the summary artifact alone. A missing pull request skips only its own row; any other GraphQL error still leaves the read's candidates unwritten. The job gains `pull-requests: read` for that read.
