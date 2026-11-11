---
bump: minor
---

### Changed

- `/planning:wayfind` names fidelity (how concrete an artifact is, from discussion to working code) and settles each decision item with the cheapest artifact that answers its question, never below the level where it answers nothing; that artifact sets the item's type.
- The Brief's appetite now acts on the solution side: `/planning:plan` writes an Appetite fit line and cuts scope that does not fit, `/planning:brainstorm` weighs candidates against it, and plan review and the plan-reviewer agent ask whether the plan is within appetite. Nothing changes when there is no Brief or the appetite is not assessed.
