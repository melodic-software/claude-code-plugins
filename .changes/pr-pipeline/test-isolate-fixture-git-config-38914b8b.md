---
bump: patch
---

### Changed

- `scripts/run-test-file.sh` runs a test with git reading a fixed test config (a test identity, commit and tag signing off, no system config) in place of the host's, so a host that signs every commit cannot fail a fixture commit.
