---
bump: minor
---

### Added

- The `/planning:interview` page ends a round's first question with a round index table: `Q`, a one-line recommendation, the basis and the main alternative, one row per question not held for research.
- The page's round header card shows a `Held:` line that names each question still held for research, from this round or an earlier one, and what it waits on.
- `round.sh ensure-running --pacing` records the `question_pacing` setting as `meta.questionPacing`, and the page start command passes it. Under `single` pacing the session posts the round's questions one at a time, the page shows no round index, and each later question carries the `Held:` line.
