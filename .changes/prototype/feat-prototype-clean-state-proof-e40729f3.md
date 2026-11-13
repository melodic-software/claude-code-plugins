---
bump: minor
---

### Added

- A shared clean-state proof in the prototype discipline: before handing a prototype over, the
  agent starts it from a clean state, drives it itself through an ordered check list of actions
  and expected results, leaves it clean, and hands the person that list before asking for a
  verdict. `/prototype:pressure-test` and `/prototype:explore-directions` both run it.
- `/prototype:explore-directions` mockups open on seeded synthetic data with Seed, Clear and Reset
  controls, plus pagination, filter and sort toggles when a variant renders a list
  (`reference/data-controls.md`).

### Changed

- The `/prototype:explore-directions` handover has five parts: the check list now comes before
  the reply template. The shared-interview handover carries the check list too.
- Eval cases `ed-offline-mockup-handover` and `pt-html-demo-offline` grade the check list, and the
  mockup case checks for the data controls.
