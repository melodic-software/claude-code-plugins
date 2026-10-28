---
bump: minor
---

### Added

- `export-brief` writes an `### Intent` section above the Brief's `### Goal`. It opens with the user's goal paragraph from the restatement's new `intent` section, or `none stated`. It then lists the text of each `ask`, `note` and `own` event word for word, in event order and under its `Q<N>`, and leaves out undone and withdrawn events and the note that gave the goal paragraph. An answered row that took the recommendation gets a `why:` line from its question's `basis` under its Constraints entry.
- The interview asks for the goal in the user's own words before the confirmation restate and sends it as `intent`, which the restatement box shows. The terminal Brief template carries the same `### Intent` section, and `/planning:plan` reads it first.
