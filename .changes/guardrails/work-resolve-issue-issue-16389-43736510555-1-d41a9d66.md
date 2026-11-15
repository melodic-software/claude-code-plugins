---
bump: patch
---

### Fixed

- The `reference-verify` pre-push entry no longer judges lines that a merged branch brings in when one of the remote's tracking refs already holds them, for any branch. Before, it skipped such lines only for a merge of the default branch, so a push that merged a long-lived integration branch ran the verifiers on every file that branch changed. That could take minutes, long enough for the remote to drop the idle ssh connection. The entry now uses the same rule as `pre-push-content`, and the README row also names the `Connection to <host> closed by remote host.` failure.
