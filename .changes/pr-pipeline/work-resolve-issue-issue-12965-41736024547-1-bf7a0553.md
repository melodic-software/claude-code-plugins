---
bump: minor
---

### Added

- pr-verify can pass the last pull request of an issue split across several. A closing pull
  request's body names the earlier ones on a `Siblings: #<a>, #<b>` line. resolve-pr credits each
  one GitHub shows merged into the base in this repository, closing no issue, with a `Refs:` line
  naming the closing issue and a body unedited since the merge unless a trusted person edited it
  last. It lists each one with its body in the spec entry's `credited_siblings`. The verifier and the
  whole-spec judge then judge the diff only for the done-when items those siblings did not deliver.
  A named sibling that did not merge, or whose `Refs:` names another issue, earns no credit, and a
  `Refs:` pull request must still name the work that remains. The merge gate needs no change.
