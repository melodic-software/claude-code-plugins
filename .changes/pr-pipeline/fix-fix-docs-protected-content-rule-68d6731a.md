---
bump: minor
---

### Changed

- The `docs` patch row's new `protected-content` content rule keeps fix-docs out of generated regions and frozen records. It leaves out each git hunk that touches a `BEGIN GENERATED`/`END GENERATED` region or writes a marker line, keeping an insertion right before a BEGIN or right after an END. It leaves out the whole change, mode included, to a file in the `released` or `historical` tier of `docs/conventions/docs-naming.yaml`, to a file whose markers do not pair, and to one whose rebuilt regions would differ from the head's. Each drop prints a `::warning` naming the file and, for a hunk, its generator; the rest of the patch still pushes, and a patch left with no change pushes nothing and skips `not-applicable`.
