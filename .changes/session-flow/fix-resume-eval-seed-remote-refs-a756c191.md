---
bump: patch
---

### Fixed

- Resume-eval case seeds now create the remote branches, tags and PR head refs their story names, so a resumed reader answers those lookups locally instead of reading the remote.
- Resume-eval sessions now run every shell command in the Bash sandbox with no allowed network host, a strict allowlist and no unsandboxed retry, and refuse to start when the sandbox is unavailable, so a reader can read the run's local origin while any network attempt fails at the OS level. The blanket `git ls-remote` deny is narrowed to its URL and user@host forms, kept beside the sandbox with the curl, wget, WebFetch and WebSearch denies.
