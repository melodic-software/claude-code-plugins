---
bump: patch
---

### Changed

- `select-trusted-text` reads a listed author's pull request title renames in the same GraphQL request as its closing issues, one request fewer per judged job. Later pages of either list are still read on their own under the same 50-page cap, and the renames are still checked only when the title could be kept.
- pr-verify's resolver checks a failed upstream run's jobs before it reads the commit's pull requests, so a run that did not fail only on holds an approval lifts or `do-not-merge` skips with one API call fewer. Such a run now reports `not-a-passing-run` even when its pull request is a draft or another author's, where it reported `draft` or `author-not-lane` before.
