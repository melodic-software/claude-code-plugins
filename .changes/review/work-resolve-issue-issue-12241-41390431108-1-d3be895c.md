---
bump: minor
---

### Changed

- `code-reviewer` and `security-reviewer` now write their full report to the findings path the caller passes and reply with a short fenced block: `artifact:`, `persistence: written | by-value`, counts by severity, and a summary of one paragraph at most. With no path, or when the write is refused, they reply with the report by value. Each gains `Write`, limited to that one file outside its agent memory directory, and writes only a path shaped `reviews/<branch-slug>/<stamp>-<agent>.md` from a single `Findings path:` line.
- `/review:quality-gate`, `/review:fanout` and the `fanout-sweep` workflow (new `findingsPaths` argument) pass that path and read the report back from the file. The caller's side is in `reference/reviewer-handback.md`. The Stage-0 extractor reads only the findings files its brief lists.
