---
bump: patch
---

### Changed

- pr-merge's credential scan of the carried artifact listing takes under a second instead of about 10 minutes, so it no longer holds the pr-merge concurrency group. Every credential scan step in pr-merge.yml now times out after 2 minutes; a timed-out scan sets no `clean` output, so the upload it guards is skipped.
