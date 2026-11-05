---
bump: minor
---

### Added

- draft-goal-condition checks readiness before an unattended run

  When the run will be left alone, the skill checks four conditions from
  evidence itself (done or watched once, the user's tools and signals,
  a check per stage that can stop the run, repeated failures already
  caught) and asks only about a condition that fails. Under --unattended
  it records the failures and recommends a watched run. It then emits a
  run contract beside the condition: goal, predicate, isolation,
  permissions granted before launch, and the dead-end write-up.
