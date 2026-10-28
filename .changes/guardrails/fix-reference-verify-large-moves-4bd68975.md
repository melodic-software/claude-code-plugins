---
bump: patch
---

### Fixed

- The pre-push reference check judges a file over 128 KiB instead of skipping it: the file's text reaches jq as a file, not as one command-line argument, which the kernel refused ("Argument list too long").
- The pre-push reference check judges a file added as a copy of a file the push also changes (a doc moved with a stub left at its old path) on the lines it adds, as it does a renamed file, so citations the doc already held are no longer reported as new.
- `stale-path-verify` reads its deleted-path list in one pass (a rebuild took about 25 s on this repository's history, now well under a second) and lists the tracked files only for a root-level citation that has an extension.
