---
bump: patch
---

### Fixed

- pr-verify judges a pull request whose `ci-status` fails only on the `do-not-merge` label, alone or beside a hold an approving review of the head lifts, so a session holding the pull request gets a verdict on each head it pushes. resolve-pr's `heldOnly` accepts a failed `Check the pull-request contract` step when its only error is check-contract's `do-not-merge` line. `ci-status` still fails while the label is on, and the merge queue still removes the labeled pull request ([#10819](https://github.com/melodic-software/claude-code-plugins/issues/10819)).
