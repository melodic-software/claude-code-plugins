---
bump: minor
---

### Added

- The interview page shows Claude's read-back of an answer under that answer, with a Confirm reading button that sends the new `confirm-reading` event. The event names the answer and the read-back the page showed (`answerSeq`, `readRev`), and the server refuses one Claude has replaced since, so a confirmation never settles a reading the user did not see. R-D in the interview skill's `context/surface.md` now points to the read-back rule in `context/loop.md` "Drift check" and adds only the page mechanics.
- Each recommendation on the interview page shows the `Flips if:` line from its basis, or `Flips if: not stated` when the basis has none. The Why panel leaves that line out.

### Changed

- The interview page's final confirmation reads "Confirm, or give the numbers to change." Beside Confirm, the user types question numbers (`Q3, 7`) and presses Change these, which sends `Change Q3, Q7`. Free text is refused. This replaces Something's off.
