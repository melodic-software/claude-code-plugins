---
bump: patch
---

### Fixed

- `/evals:plugin-eval` preflight no longer prints a cleanup loop over every `claude-eval-*` directory in the temp directory. When two sessions share a `TMPDIR`, that loop deleted the other run's live or kept sandboxes. Preflight now reports the leftover count and size and points at the removal by results file, which removes only the sandboxes one run's `tracePath`s name, by literal path.
