---
bump: minor
---

### Added

- plan-panel: configurable rubric, judge split and left-behind ideas

  The workflow takes a rubric argument, set from the new
  plan_panel_rubric key, and keeps today's four criteria as the default.
  It returns judge_winners and judges_split, so a split panel is not
  hidden by the mean, and left_behind, the runner-up ideas the
  synthesizer considered and did not graft, each with why. The plan
  skill now scores the drafts itself before reading the judges' scores.
