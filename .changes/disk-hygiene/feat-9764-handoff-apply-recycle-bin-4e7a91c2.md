---
bump: minor
---

### Added

- **`handoff-apply` removes one approved tier per call, and on Windows it sends each path to the Recycle Bin** ([#9764](https://github.com/melodic-software/claude-code-plugins/issues/9764)). The Windows manual lane cost about one prompt and two or three tool calls per deleted path. Now one `handoff-apply` per tier takes a repeatable `--path` and a required `--tier`, and its hook `ask` lists the tier, the count and every path, so that prompt is the tier's approval. Inside that one process each path is re-verified just before its removal, and a path whose verdict is not `clear` is skipped and reported. On Windows the engine recycles through the shell's `IFileOperation` and refuses a path the shell reports it cannot recycle, leaving it in place. If the shell deletes one outright anyway, the batch stops there. A batch whose volume reports no Recycle Bin removes nothing, and an error partway stops the batch without losing the report of what was removed. The report's `permanent_delete_used` says whether any removal was permanent.

### Changed

- **`handoff-apply` refuses a whole batch when `--tier` ranks above a path's lowest hint `confidence_ceiling`, or when a path has no hint.** Nothing is removed and the call exits 2. That includes a throwaway Git checkout with no hint: add a hint for it in a policy overlay and rescan before removing it. `--vcs-evidence` is now optional, as it is for `handoff-verify`. The report lists a `verdicts` entry per path in place of the single `path` and `verdict` fields.
