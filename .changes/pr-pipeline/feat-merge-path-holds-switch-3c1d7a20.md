---
bump: minor
---

### Added

- `merge.diff-check.path-holds` turns off every path-based merge hold with one switch. Absent or
  false (the default, and this repository's setting by owner decision Q15), a changed path no
  longer holds a pull request for its path alone. This covers the risk scorer's path floor,
  denied-paths and `review-path:` holds, enable-auto-merge's hold paths and ci-status's
  merge-holds step. A standing refusal that names only hold paths comes off without an approval.
  Set it to true to bring every one back. Cost paths, unsafe or aliasing paths, the manifest
  review, the trusted-actor widening, body holds, vetoes and `do-not-merge` still hold. The gate
  report (`risk.pathHoldsSkipped`), enable-auto-merge's log and merge-holds.mjs name each hold
  the switch skipped.
