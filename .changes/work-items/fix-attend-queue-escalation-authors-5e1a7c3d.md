---
bump: minor
---

### Fixed

- `reference/escalation-marker.md` now defines the trusted escalation authors in one place: the session's write identity, the target's `merge.agent-identity` from `docs/conventions/pr-pipeline.yaml` on its default branch, and `<lane_app_slug>[bot]` when that option is set. `/work-items:attend-queue` and `reference/item-content-trust.md` point at it, so markers the CI lanes post as the lanes App list as escalated, and a marker from any other author is reported as a suspected spoof.
- `/work-items:attend-queue` lists open pull requests carrying the human-gated label beside issues, through the github adapter's new "List pull requests" operation, since `list-items` returns issues only. A pull request row takes the answer comment and loses the human-gated label, never the autonomous-eligible role or a `work-class:` label.
