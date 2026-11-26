---
bump: patch
---

### Fixed

- A person's approval carries over base merges at any pull request size. `merge-holds.mjs` `liftersOf` reads every compare of the approval carry with its commits paged past the unpaged 250 (`wholeCommits`); `exactBaseCarry` judges the merges and base ranges on their two `application/vnd.github.diff` texts when either listing reaches 300 files or gives a file no patch, the tree modes checked for every file the merges' diff names; and `ungatedSince` judges a push of 300 files or more on the files of its diff, with the same hold-path, review-floor and `CARRY_REFUSES` checks. A page or diff that does not read, a list still shorter than `total_commits`, or a diff that does not parse or names fewer files than its listing carries nothing.
