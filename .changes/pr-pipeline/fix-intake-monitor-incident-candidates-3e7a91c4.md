---
bump: patch
---

### Fixed

- Intake refinement counts an open factory-monitor incident as a duplicate candidate, so a person's issue about a failure the monitoring lane already tracks is flagged. A github-actions[bot] issue counts only while it is open and its first body line is the `<!-- factory-monitor key=… fp=… -->` marker; other github-actions[bot] issues are still left out.
