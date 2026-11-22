---
bump: minor
---

### Added

- pr-verify's Check Intent defers a first attempt while the GITHUB_TOKEN window is projected to run short before the judgment ends (a second `check-kill-switch` gate with `defer: "true"`, `defer-job: check-intent`, after the resolver and the trigger gate, so a run that would skip never defers). Its `Note the deferral` step prints `cause=defer reset=<epoch>`. The lost-run reconciler reads that step as a hold, waits until a minute past the reset, and re-runs the run once, recorded, in the same band of at most 12 re-runs a pass as the deferred hosted reviews ([#17460](https://github.com/melodic-software/claude-code-plugins/issues/17460)).

### Changed

- The lost-run reconciler ticks every 15 minutes (`4,19,34,49`) and runs one pass per GITHUB_TOKEN window: the first tick at least 90 seconds and at most 30 minutes after the window's reset, read from GET /rate_limit, so deferred work is re-run at the start of the next window wherever the reset has drifted. Other ticks read nothing else and stop. That pass is not paced: it spends the fresh window. A tick whose reset read fails runs the pass unless one finished in the last hour.
