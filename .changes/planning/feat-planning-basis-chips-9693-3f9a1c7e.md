---
bump: minor
---

### Added

- **The interview page shows a chip for a question's basis outcome.** A `basis` that leads or ends with `Verified` or `Judgment` now renders a differently styled chip beside the recommendation, so a judgment call no longer reads like a verified one.
- **`round.py` warns on a basis with no outcome label and on a bare local-file reference.** `add`, `add-round` and `--check` warn, never refuse, when `basis` carries no `Verified`/`Judgment` label (a `Withheld:` recommendation is exempt), and when `facts`, `basis` or a recommendation names a local file or says "see X" with no quote, list or link in the same field.

### Changed

- **The interview Source rule covers any referenced scope.** Lists, item numbers and file sections a decision rests on go in full into the question box, and an external source gets a clickable link.
