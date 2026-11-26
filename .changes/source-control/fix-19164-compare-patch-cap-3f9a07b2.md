---
bump: patch
---

### Fixed

- The merge gate's approval and cost-decision carries (`babysit_merge_policy.same_net_change`, `carried_lifters`, `_carries`) judge a pull request whose compare lists 300 files or more: when either listing caps or gives a file no patch, the two compares' `application/vnd.github.diff` texts decide, every file's patch and mode compared (`diff_files`, `needs_diff`, `_cap_diffs`), as `merge-holds.mjs` does. A binary file, a diff that does not parse, or a diff naming fewer files than the pull request changes carries nothing.
