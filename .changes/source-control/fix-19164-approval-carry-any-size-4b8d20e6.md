---
bump: patch
---

### Fixed

- The merge gate's approval carry (`babysit_merge_policy.carried_lifters`) carries at any pull request size, as `merge-holds.mjs` does: its compares are read with commits paged past 250 (`_whole_commits`), `exact_base_carry` judges merges and base ranges at 300 files on their two diffs, and `ungated_since` judges a push of 300 files or more on the files of its diff. A page or diff that does not read, or a diff naming fewer files than its listing, carries nothing.
