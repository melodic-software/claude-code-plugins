---
bump: patch
---

### Changed

- `block-unresolved-pr-merge` reads the gate's check run as `CI Status`, else `ci-status` on a head
  tested before the rename, and treats the `ci-status` alias of a superseded `CI Status` in the
  same Actions run as superseded with it.
