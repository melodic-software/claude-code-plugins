---
bump: patch
---

### Fixed

- `detect.sh` retries its prose extraction once when awk aborts with exit status 134. gawk returned that status after `fatal error: internal error` on trees that passed an unchanged rerun. Before it retries, it prints a notice on stderr. Any other awk failure, or a second abort, still stops the scan with `prose extraction failed; nothing was scanned` and exit 2.
