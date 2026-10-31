---
bump: patch
---

### Fixed

- The usage check before `/source-control:pull-request` picks who watches a PR now covers a snapshot with one window: every window in the file below the line counts as clear, where the rule named "both windows".
