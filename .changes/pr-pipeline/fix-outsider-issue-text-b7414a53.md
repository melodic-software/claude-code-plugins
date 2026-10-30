---
bump: patch
---

### Security

- The issue lane no longer works from an outsider's issue text once a listed human applies
  `agent-ready`: the admit job's `check-blockers.mjs` stops the run for good, through the existing
  `Stop on untrusted provenance` step, when the issue's author is neither a listed human nor the
  lanes App. `report-skip` then runs `report-outcome` with `dimension-skip: outside-author`, which
  removes `agent-ready` and comments that a listed human re-files the work as a new issue, adding
  no label. `write-issue.mjs` also fails the run on such an issue. Admission, intake refinement and
  verdicts, the issue lane and intake re-entry now share one author check, `admit.mjs`
  `authorAdmitted`, which also refuses an issue with no author.
