---
bump: minor
---

### Changed

- The monitoring lane keeps one rolling issue per signal, `Monitoring: <signal>`, in place of one issue per signal and key. It rewrites the body and adds a comment only when the signal's state changes, closes the issue when the signal clears, and reopens the same issue when it fires again; it never files a second. GitHub incidents are listed in the run summary and no longer filed. Open issues from the per-key form are closed as not planned, pointing at the signal's rolling issue (`.github/scripts/maintenance-monitor-signals/`).
- The lane sweep writes its findings into one rolling digest issue, `Lane sweep: open findings`, in place of filing an issue per finding. Each daily sweep replaces the body, so a fixed finding drops off; when a unit's findings were not read, earlier entries carry over (`.github/scripts/maintenance-audit-lane-runs/file-findings.mjs`, `findings.mjs`).
- Neither lane labels its issues `needs-triage` any more; each keeps its `source:` label. Each rewrite takes `agent-ready` off the rewritten issue, since a person vetted the earlier text. The [pr-pipeline README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane) has the rules.
