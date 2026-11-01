---
bump: major
---

### Changed

- **Breaking:** the work-item tracker bundles only the `github` and `local-markdown` adapters. `jira`, `gitea` and `linear` now ship as seeds under `tools/work-item-tracker/seeds/`, and the consuming repo owns its copy. `/work-items:setup apply` runs the new `seed-copy.sh`, which copies the bound provider's seed into `<repo root>/tools/work-item-tracker/adapters/<provider>/` with a `.seed-hash` record. On a re-run it fast-forwards a copy nobody edited, and for an edited one it prints the diff and writes nothing. A repo already bound to one of the three gets exit `3` from the seam, naming the setup step, until it runs `/work-items:setup apply` once (#11873).
