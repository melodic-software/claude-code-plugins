---
bump: patch
---

### Fixed

- Resume-eval case seeds now create the remote branches, tags and PR head refs their story names, so a resumed reader answers those lookups locally instead of reading the remote.
- Resume-eval sessions may now list and fetch the refs of a named remote (`git ls-remote`, `git fetch`, with or without `-C`), so the auto-mode classifier no longer refuses a reader confirming them. URL and user@host forms stay denied (and host:path for `ls-remote`), and so does re-pointing a remote (`git remote add`, `git remote set-url`, `git config` on `remote.*`).
