---
bump: minor
---

### Added

- babysit-prs: the pr-merge lane's post-merge check now starts from a floor anchor that
  pr-merge.yml's post-merge-dispatch job keeps as the `pr-merge-post-merge-anchor` artifact. The
  anchor moves past merges the check judged final from their runs. An unverified merge holds it,
  and so does a merge counted only by its settled marker. A missing or refused anchor falls back
  to today's floor, so a long verified history no longer stops the lane with
  `merged-history-truncated`.
