---
bump: minor
---

### Added

- `/planning:design` runs a variation-point pass for every external integration and domain category (always for integration, module and system scopes): two questions (likelihood of a second variant, cost of change), three verdicts (abstract now, contain now and abstract later as the default for anything external, leave inline for internal one-offs), and a leak test for every abstraction. An agent never picks abstract on its own; unattended, it contains and records the question as a human decision. The rule and its canonical sources live in the new shared `reference/variation-points.md`.
- `/planning:plan`'s design section audit and plan reviewer check that every external integration has a variation verdict.
