---
bump: minor
---

### Changed

- babysit-prs: `evidence --lane-link --lane-reviews` takes a lanes App pull request whose changed files are exactly the repository's new `merge.baseline-file` setting (`docs/conventions/pr-pipeline.yaml`) with no issue link and no verdict, and still scores its risk. Unset, it takes none; the base and the default branch head must name the same file. Only a missing or malformed link is set aside: an unreadable link or a trust hold on the linked issue still refuses. `babysit_merge_policy.baseline_only` is the rule.
