---
bump: patch
---

### Changed

- **`plugins`: `cache-content-check.sh` no longer reads its large streams with `mapfile` or `read`** ([#12982](https://github.com/melodic-software/claude-code-plugins/issues/12982)). On Git Bash those builtins read one byte per call, so one 2.3 MB `ls-tree -z` stream took about 2.5 s to read. The `ls-tree`, `find` and `check-ignore` streams are now read with one `tr` capture each and split in memory. A stream holding a path with a newline or an SOH byte is still read with `mapfile -d ''`, so such paths are compared as before. The `hash-object` batch output is split in memory too, and each record's source directory comes from a map lookup instead of a scan of the marketplace entries. Each of the three NUL streams now costs one `tr` process.
