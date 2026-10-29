---
bump: patch
---

### Security

- The issue lane no longer works from an outsider's issue text once a listed human applies
  `agent-ready`: the admit job's `check-blockers.mjs` stops the run for good, through the existing
  `Stop on untrusted provenance` step, when the issue's author is neither a listed human nor the
  lanes App, with a notice telling a person to re-file the work in their own words. Admission,
  the issue lane and intake re-entry now share one author check, `admit.mjs` `authorAdmitted`, which
  also refuses an issue with no author.
