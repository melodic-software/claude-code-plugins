---
bump: patch
---

### Fixed

- The interview surface now sets aside an accept when the session revises the recommendation the
  user accepted. `reply --rec` and `revise --rec` set aside a counted accept or hedged accept
  whose recommendation the revision changes, and record the accepted text. The question reads
  open until the user accepts again: the page shows it as needing reconfirmation and quotes the
  accepted text, and `export-ledger` writes an open row whose `aside::` names that text, never the
  revised one. `import-ledger` restores such a row still set aside. Before this, the export and
  the page recorded the revised text as the user's answer
  ([#11584](https://github.com/melodic-software/claude-code-plugins/issues/11584)).
