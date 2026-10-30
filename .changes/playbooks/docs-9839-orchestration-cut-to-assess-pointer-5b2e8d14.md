---
bump: patch
---

### Changed

- The `fable-5` orchestration chapter's "When to delegate, when to stay inline" section no longer restates the delegate-or-inline verdict that `/multi-agent:assess` and its subagent docs pointer own. It points at assess and keeps only what assess does not decide: the file-overlap and detail-needed-later stay-inline conditions, the fan-out cost weighing, and the isolation and consistency reasons. The hub's delegation line now points at assess too.

### Fixed

- The `fable-5` hub names its chapters under `${CLAUDE_SKILL_DIR}/context/`. A bare `context/` was resolved against the plugin root, so the chapter read was denied and the chapter never loaded.

### Added

- The seven delegation cases from `skills/fable-5/evals/evals.json` as `claude plugin eval` cases under `evals/`, so the before and after runs can measure them.
