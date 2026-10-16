---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer blocks on a cancelled run whose newer run of the same check was skipped (#7549).** When the newest run of a check is skipped or neutral, the guard looks back for an older completed run with a real conclusion; it counted a cancelled run as one, so an older cancelled run blocked the merge. A cancelled run no longer counts in that look-back. An older failure behind a skipped run still blocks, and a newest run that was cancelled or failed still blocks.
