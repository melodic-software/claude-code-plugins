---
bump: minor
---

### Changed

- babysit-prs: `evidence --lane-link --lane-reviews` takes a lanes App pull request whose changed files are exactly `docs/upstream/claude-code-native-surfaces.min.json` with no issue link and no verdict, and still scores its risk (owner decision Q152 (B)). `babysit_merge_policy.baseline_only` is the rule, and it matches merge-holds.mjs `baselineOnly`.
