---
bump: patch
---

### Changed

- **skill-authoring:** the negative-control step in `rewrite-a-plugin.md` passes `--own-copy-search-warns` to the run-validity gate on the degraded side only, so its search of its own copy for the removed text no longer leaves the control unmeasured.
