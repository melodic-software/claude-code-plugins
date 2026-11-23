---
bump: patch
---

### Fixed

- **babysit-prs runs Git Bash on Windows, never the WSL relay.** The post-merge lift's canary scan now runs bash by the full path the merge policy resolves.
- **The job's stop and cause files end each line in LF on Windows.** A stop recorded on Windows was written with CRLF, which the stop-file reader skipped, so later steps did not see it.
- **A stop file under a file holds every pool on Windows too.** Windows reports that path as not found; it now holds every pool, as it does on Linux, instead of reading as no stop.
