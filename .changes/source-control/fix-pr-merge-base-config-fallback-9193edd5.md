---
bump: patch
---

### Fixed

- The pr-merge gate no longer refuses every pull request whose base commit holds a `docs/conventions/pr-pipeline.yaml` the reader can no longer parse (a base from before flow mappings were rejected). It reads the merge config at the default branch head alone, reports that as `baseConfigFallback` in the decision, and still refuses when that config cannot be parsed or the base cannot be read.
