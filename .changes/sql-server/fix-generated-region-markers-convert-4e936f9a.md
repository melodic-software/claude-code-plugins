---
bump: patch
---

### Changed

- `scripts/measure-read-safety.mjs` writes its results into `reference/read-safety-measurement.md` between `<!-- BEGIN GENERATED: measure-read-safety results. ... -->` and `<!-- END GENERATED: measure-read-safety results -->`, the markers the ai-slop audit skips, so its fix pass no longer edits the measured results. The committed doc carries the new markers, and a doc with only the older `<!-- measure-read-safety:results:start -->` markers is refused before any container starts.
