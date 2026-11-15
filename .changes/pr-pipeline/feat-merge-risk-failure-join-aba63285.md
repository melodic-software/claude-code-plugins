---
bump: minor
---

### Added

- The Merge-Risk record's marker names the lane run that opened the pull request:
  `<!-- merge-risk-line head=<sha> lane=<lane> run=<run id> -->`, read from its
  `<lane>/issue-<n>-<run id>-<attempt>` branch. A marker for any other branch has neither field,
  and a record in the earlier shape still reads; the arm's next write for that head adds them,
  unless the record holds a rating and the new read is unrated. The arm reads the branch from the
  listing it already makes, so it makes no more calls.
