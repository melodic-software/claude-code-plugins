---
bump: minor
---

### Added

- pr-verify's Check Intent defers a first attempt while the GITHUB_TOKEN window is projected to run short before the judgment ends (a second `check-kill-switch` gate with `defer: "true"`, `defer-job: check-intent`, after the resolver and the trigger gate, so a run that would skip never defers). Its `Note the deferral` step prints `cause=defer reset=<epoch>`. The lost-run reconciler reads that step as a hold, waits until a minute past the reset, and re-runs the run once, recorded, in the same band of at most 12 re-runs a pass as the deferred hosted reviews ([#17460](https://github.com/melodic-software/claude-code-plugins/issues/17460)).

### Changed

- The lost-run reconciler's hourly tick waits until 90 seconds past the GITHUB_TOKEN window's reset, or runs at once when the window began at most 11 minutes ago, so each pass re-runs deferred work at the start of the next window wherever the reset has drifted. That tick is not paced: it spends the fresh window. A tick whose reset read fails runs at once and is paced as before.
