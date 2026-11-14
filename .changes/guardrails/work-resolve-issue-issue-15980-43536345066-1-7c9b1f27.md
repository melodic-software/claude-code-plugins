---
bump: patch
---

### Fixed

- **pre-push-content no longer takes minutes on a pushed merge whose diff against a parent touches many files ([#15980](https://github.com/melodic-software/claude-code-plugins/issues/15980)).** It ran git several times for every file in each parent's diff, and the remote could close the connection and fail the push while the hook ran. It now reads only the files the merge changes against every parent, one git process each, plus a fixed number of diffs per parent. A non-merge commit's files cost one git process each instead of three. A file holding a NUL byte is still judged whole for secrets.
- **pre-push-content now judges the lines a merge adds in a file that a parent other than the first holds as a symlink or a submodule.** Those lines were dropped before they were judged.
- **pre-commit-content and pre-push-content now judge a merged file whose bytes equal another parent's but whose mode differs.** Such a file was skipped as taken whole from that parent. A regular file that a merge makes from another parent's symlink, holding the link's target text, is now judged like any other file the merge changes. A file judged whole (one holding a NUL byte, or whose name holds a quote, a backslash or a control character) is now judged when only its mode differs from that parent's.

### Changed

- **pre-commit-content finds the files a merge takes unchanged from another parent with one git diff per parent, instead of one git process per file.**
