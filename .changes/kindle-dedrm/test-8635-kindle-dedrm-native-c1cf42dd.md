---
bump: patch
---

### Changed

- The manage and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Four of the nine legacy cases become five new cases: `md-setup-delegates`, `su-check-provisioning-info`, `su-apply-download-guards`, and the two halves of the apply hand-off case, `su-apply-lock-verify` and `su-apply-installer-checkpoint`. The other five were already covered by `md-share-keys-refused`, `md-cleanup-batch-library` (two cases), `md-friend-files` and `md-installer-popup`, and `md-cleanup-batch-library` now also grades the redo-cost reason and the other `--full` reversals. The manage setup case now checks the hand-off to `/kindle-dedrm:setup`, because the router no longer provisions inline. Both `evals.json` files are deleted.
