---
bump: patch
---

### Changed

- `/harness-ops:plugins sync` keeps the per-record divergence detail out of the digest it prints: `divergences.records` and the full per-path list go to `<run_dir>/divergences.<marketplace>.json`, named by `divergences.records_file`, and the digest carries `record_count`. `audit` still carries the records inline, since its scratch directory is removed on exit (#12542).
- The report's `by project path:` list names only paths present on the machine. The paths that are not present get one count line, since the stale project records section counts them; the digest counts them in `divergences.blocked_paths` (#12542).
