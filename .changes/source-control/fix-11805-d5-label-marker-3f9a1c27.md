---
bump: patch
---

### Changed

- Every D5 answer to a review finding, inline or issue-level, now carries one `<!-- d5 finding=<#> label=<LABEL> lane=<lane> -->` line per finding. Its `label` is `VALID`, `VALID-defer`, `INCORRECT`, `UNCERTAIN` or `INTENTIONAL`, so a reader can tell how each finding was answered. The own-reply filter in `review-discipline.md` §1 and in the pull-request monitor recognizes the marker, and still accepts the older classification table ([#11805](https://github.com/melodic-software/claude-code-plugins/issues/11805)).
