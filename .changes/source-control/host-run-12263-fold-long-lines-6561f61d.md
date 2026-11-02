---
bump: minor
---

### Changed

- The merge gate no longer holds a pull request for a person as `long-line-review:<path>` when its patch holds a line over 1800 bytes: the main-run review now folds such a line and reads every byte. The binder still counts no main-run verdict whose recorded longest line is over 1800 bytes.
