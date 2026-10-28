---
bump: patch
---

### Fixed

- `/evals:plugin-eval read` now ends by removing the `--keep-temp` sandboxes of the run it read, once the reading and any trace review are done, so they no longer pile up until a later preflight. It removes only the `claude-eval-*` directories that hold that file's `tracePath`s, by literal path and never by glob. When the removal is refused, it prints the per-sandbox command for those paths. The preflight leftover count is unchanged.
