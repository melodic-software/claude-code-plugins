---
bump: patch
---

### Fixed

- work-unblock's hourly sweep relabels a red-main fix issue that post-merge-demotion-alert.yml
  reopened on a repeat failure, so work-resolve-issue starts on it. The reopen keeps `agent-ready`
  but runs on that workflow's `GITHUB_TOKEN`, which starts no run. The sweep matches the issue's
  `<!-- post-merge-fix check=... -->` first line and the workflow's recurrence comment, both
  `github-actions[bot]`'s, logs how many match, and has the lanes App post a record naming that
  comment, then remove and re-add `agent-ready`: once per recurrence comment, inside the
  five-a-run cap, and never on an issue that is held, has an open lane PR or a lane run in flight,
  or had `agent-ready` added since the reopen.
