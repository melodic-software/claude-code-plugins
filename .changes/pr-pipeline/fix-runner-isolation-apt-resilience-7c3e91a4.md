---
bump: patch
---

### Fixed

- `setup-runner-isolation` no longer fails a run while the Ubuntu mirror is slow. It installs bubblewrap and socat from a per-image Actions cache when every cached deb matches the SHA-256 in the image's own package lists, else with `apt-get` from those lists without an index refresh, else after `apt-get update` (three tries), within 540 s. It drops the apt timeout overrides that delayed the image's failover to `archive.ubuntu.com`, and now fails red when either `bwrap` or `socat` is missing, not only `bwrap`.
