---
bump: patch
---

### Added

- Outcome eval cases for `audit-derivability`, `audit-encapsulation`, `audit-noise`, `audit-progressive-disclosure`, `extract-ssot`, `rename-references`, `write-for-agents` and `write-for-humans`, and frozen trigger-probe sets for every model-invoked skill.

### Changed

- Tightened the model-invoked skill bodies and their spokes to the skill criteria, with no rule removed; `extract-ssot` is unchanged. `compress compare` now says to print the labeler's rows and literal `VERDICT:` line verbatim, and `rename-references` says to run every sweep through the Grep tool, reading a file only to confirm a hit.
