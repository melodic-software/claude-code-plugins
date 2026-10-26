---
bump: patch
---

### Changed

- intake-triage.yml now adds the `needs-triage` floor label itself, in an `intake-label-needs-triage` job that calls the same pinned ci-workflows reusable, so one run per issue event does both and the separate intake-label-needs-triage.yml workflow, with its own kill-switch and born-triaged jobs, is gone. The workflow also takes `reopened`: on a reopen only the kill switch and the floor label run, since born-triaged and the triage job are gated to `opened` (or a dispatch from main). A dispatch never adds the floor label. Each job keeps its own permissions; the label job holds `issues: write` only, as before.
- born-triaged reads its gate before it resolves the triage model, so a model config that fails still leaves the floor label its skip.
- The lost-run reconciler watches intake-triage.yml for a failed first attempt of an issues run and re-runs its failed jobs only when the `intake-label-needs-triage` job is the only one that failed. A run where triage, a gate or a broker job failed is left alone, so none of them runs again as github-actions[bot]. It lists a candidate's jobs only while the run ended in the last 2 hours (four passes), so a run it leaves alone costs at most 4 job listings, not one on every pass of the 24-hour lookback.
