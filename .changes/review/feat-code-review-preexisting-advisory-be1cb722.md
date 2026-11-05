---
bump: minor
---

### Changed

- `/review:code-review` reports a pre-existing defect on an unchanged line that a changed line calls, instead of excluding it: as an advisory summary finding with no inline comment, so it never holds the merge, and the PR author places it. Only a severe one (data loss or corruption, a crash, a broken path users rely on) that the pull request can fix is a blocking inline finding, anchored on the changed line that calls it. A defect that did not reproduce on the base branch stays an ordinary finding the change introduced. Issues on unchanged lines that no changed line calls stay excluded.
