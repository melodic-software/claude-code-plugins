---
bump: minor
---

### Added

- The `/work-items:work` bug path keeps step 2's inspection read-only, and a fresh-context subagent confirms each reproduction capture shows the named broken state; a capture it does not confirm counts as a run that did not reproduce.
- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/work-items.yaml`, read from the default branch by `lib/read-verification.sh --file docs/conventions/work-items.yaml` and validated by `schemas/work-items.schema.json`. Under `light` and `off`, the capture check dispatches no subagent and records `verification: skipped (<level>)`.
- Eval cases `wk-bug-report-shape-edited-in-place`, `wk-bug-light-skips-capture-check` and `wk-bug-report-ignores-foreign-marker`.

### Changed

- The bug path's report comment (first line `<!-- work-items:investigation outcome=<outcome> desired=cause-named -->`) now covers both modes, not only `investigate`, and is edited in place through the adapter's comment edit rather than followed by a second comment. The run edits it by the id it kept, or finds it by its first line among comments authored by its own write identity only; it never edits another author's comment. In full mode the report posts before the dispatch, and a run whose brief has no Root cause field records the new outcome `cause-unconfirmed`. It adds a status line rewritten at each later step, the repro count and surface, a test-gap line, an instruction to the fixing agent, and the item's report quoted as data.
