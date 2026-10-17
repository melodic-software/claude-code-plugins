---
bump: patch
---

### Fixed

- `audit` and `fix` skip generated regions, from a standalone `<!-- BEGIN GENERATED: ... -->` line through its `<!-- END GENERATED: ... -->` line. The detector, the closing cross-check and the rubric fan-out's cue counts no longer read them, rubric subagents are told to skip them, and the fix flow, rubric and voice rewrites included, no longer edits them, so the `pr-refine / fix-docs` lane stops hand-editing the plugin-options README block that `scripts/sync-plugin-options-docs.py` owns and failing `check-plugins` with `STALE options docs` (#7554). A region with no END line is reported on stderr.
