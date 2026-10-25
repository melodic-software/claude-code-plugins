---
bump: minor
---

### Added

- `round.sh export-brief --into <PLAN.md>`, in place of `--out`, replaces only PLAN.md's `## Brief` section, from its heading to the next `#` or `##` heading outside a fenced block, and keeps every other byte of the file, its line endings included ([#9912](https://github.com/melodic-software/claude-code-plugins/issues/9912)). Text between `## Brief` and its first subheading, such as a start-fresh scope-change note, stays as written, and fenced blocks are read as `check-open-questions.sh` reads them. A PLAN.md that does not exist yet gets the whole export; one with no `## Brief` heading, more than one, or a fenced block that never closes is refused unchanged. The interview's wrap-up (`context/surface.md` step 2) uses it in place of merging the export by hand.

### Fixed

- `interview` (SKILL.md Steps 3 and 4, `context/loop.md`, `context/surface.md`) no longer implies the `--brief` gate catches a Brief edited after a Confirm: the gate reads only the `Restatement:` stamp, so the docs now say it cannot see such an edit and that the edit still needs a new `restate`, a fresh Confirm and another export.
