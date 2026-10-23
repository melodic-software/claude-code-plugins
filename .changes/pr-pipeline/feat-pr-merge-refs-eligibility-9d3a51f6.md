---
bump: minor
---

### Added

- pr-verify's resolver gives the verifier the one issue a plain `Refs: #<n>` line names as the spec of a pull request that closes no issue, by the same rule the pr-merge gate reads (`refsIssue`, kept equal to `babysit_merge_policy.refs_issue` by `test_verify_rules_sync.py`), and the prompt's file descriptions say so. The judging standard is unchanged: a partial slice is judged as a closing pull request is.
