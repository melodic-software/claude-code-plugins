---
bump: minor
---

### Changed

- `verify-scripts` may be set on a `prepare: ci-context` skill. The read runner stages each listed script's base copy behind its wrapper under `.lane/verify`, read-only and denied to the file tools, and the preamble names the wrappers as the only way to run those scripts. `fix-ci` lists `plugins/planning/scripts/repin-digests.sh`, so a digest pin the pull request's own diff moved is re-pinned by the base's script, never by one the pull request can edit.
