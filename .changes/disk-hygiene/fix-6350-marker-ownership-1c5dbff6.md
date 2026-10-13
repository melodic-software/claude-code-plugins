---
bump: patch
---

### Security

- The no-Python notice's once-per-session marker is trusted only in a real directory this user owns. Another local user could create the tmp fallback directory (`${TMPDIR:-/tmp}/disk-hygiene-guard-no-interpreter/`) first, or a symlink in its place, and silence the notice for every session. Such a directory is now neither read nor written, so the notice still shows. The guard's denies were never affected.
