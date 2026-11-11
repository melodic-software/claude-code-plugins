---
bump: patch
---

### Fixed

- `setup-runner-isolation` no longer stalls on a slow Ubuntu mirror's index refresh. It installs bubblewrap and socat from the image's own package lists first, and runs `apt-get update` only when that fails (three tries), all within 540 s. It drops the apt timeout overrides that delayed the image's failover to `archive.ubuntu.com`, and now fails red when either `bwrap` or `socat` is missing, not only `bwrap`.
