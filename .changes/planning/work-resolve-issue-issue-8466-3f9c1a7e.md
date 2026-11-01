---
bump: minor
---

### Changed

- `/planning:interview`: when a dispatched agent's or background task's output lands after a round was shown, the next message that presents a question ends with every open question in full, the changed one marked, in place of a one-line pointer for the untouched questions. Questions that do not wait on a pending result are still asked without waiting. The rule is `docs/contracts/async-round-presentation/README.md` in the marketplace.

### Added

- Eval case `late-return-restates-every-open-question-in-full`.
