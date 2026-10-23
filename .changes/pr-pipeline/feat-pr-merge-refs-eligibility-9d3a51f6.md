---
bump: minor
---

### Added

- pr-verify's resolver gives the verifier the one issue a plain `Refs: #<n>` line names as the spec of a pull request that closes no issue, by the same rule the pr-merge gate reads (`refsIssue`, kept equal to `babysit_merge_policy.refs_issue` by `test_verify_rules_sync.py`), and marks each spec entry's `spec_kind` (`closes`, `refs` or `pull-request`), which the verdict records as `spec_kind`. The verifier judges a `Refs:` issue as a partial slice (owner decision 2026-10-23): only the part the pull request body says it delivers, in the issue's scope, correct and coherent, with the body naming what remains; a body naming no delivered part or no remaining work, or claiming the whole issue, fails. Closing issues are still judged whole, and the spec trust rules are unchanged.
