---
bump: minor
---

### Changed

- The `docs` patch row's new `protected-content` content rule keeps fix-docs out of generated regions and frozen records. It leaves out each change inside a `BEGIN GENERATED`/`END GENERATED` region, and the whole change to a file in the `released` or `historical` tier of `docs/conventions/docs-naming.yaml` or one whose markers the patch unpairs or alters. Each drop prints a `::warning` naming the file and, for a region, its generator; the rest of the patch still pushes.
