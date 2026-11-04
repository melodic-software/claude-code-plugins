---
bump: patch
---

### Fixed

- The run-everything sweep waits for the `review:fanout-sweep` workflow's completion notification and takes each leaf's text from the returned `raw` array or its findings file, instead of listing or reading the workflow's run directory. Those run-directory reads were denied in eval runs, which made the reviewer-diversity suites invalid.
