---
bump: patch
---

### Fixed

- The red-main report names every red full run since the last green one that has no report on the log, so a report the repository-wide concurrency group cancelled while pending is seen in the next report, whose range re-decides over its merges.
- The red-main report takes the oldest `github-actions[bot]` issue carrying the log marker as its log, and counts only that account's comments on it (matched by user id) toward the daily cap and the dedupe, so a newer issue carrying the marker can neither take the reports nor reset the cap.
