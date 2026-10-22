---
bump: minor
---

### Added

- `models.issue-dimensions.complexity-profiles` maps an issue's Complexity to the profile its run starts on. This repository sends high Complexity to the new `code-xhigh` profile (Opus at effort xhigh); low, medium and unset keep the activity's default.
- A profile's `escalate-to` names the profile one model rung up, which a run resolved at resolve-config's new `model-rung` input 1 takes instead. `code-fix` escalates to `code-xhigh`; nothing escalates past it.
- fix-ci retries once one rung up: a run that changed nothing and escalated only `unfixed` or `not-reproducible` checks skips apply-patch with the new `rung-up` reason instead of labeling the pull request, and the dispatcher sends one more fix-ci run on that head at `model-rung` 1. `protected-path`, `weaken-required`, `flaky` and any escalation of the retry still go to a person.

### Changed

- The Fable rung above `code-xhigh` stays off: no profile names `fable` or `best`, pending an owner decision on a per-week Fable allowance for the lanes.
