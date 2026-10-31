---
bump: minor
---

### Added

- `/planning:interview`: a question stores the constraint ids its recommendation was checked against as `checkedAgainst`, set by `add` and `revise`. A newer constraint marks every open and answered question without it `Upstream changed`, the Constraints panel says whether the round's recommendations are current, and the exported ledger row ends `stale:: C<N>`. `check-open-questions.sh` then reports `stale=<n>` and exits 1 until a `revise` naming the constraint or a `reconfirm` clears the row. A question or ledger without the list reads as before. ([#5769](https://github.com/melodic-software/claude-code-plugins/issues/5769))
