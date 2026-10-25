---
bump: patch
---

### Fixed

- `round.sh export-brief` no longer writes a decision twice or exports a replaced one ([#9901](https://github.com/melodic-software/claude-code-plugins/issues/9901)). An answered row gets no Constraints line of its own when a line of the confirmed restatement's constraints or decisions recap names its `Q<N>` and holds its whole current answer; a recap line cut short, or taken before the answer changed, keeps the row's own line. A row a newer question superseded stays in the ledger and is no longer exported to Out-of-scope, which `/planning:plan` treats as approved, nor its commitments to Captured assumptions. The decisions line the replacing row leads ends `; replaces Q<N>`.
