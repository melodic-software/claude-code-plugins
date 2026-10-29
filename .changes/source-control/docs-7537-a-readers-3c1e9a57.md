---
bump: patch
---

### Fixed

- `write-changelog-fragments.sh` writes a fragment for a listed convention whose changelog is at `docs/contracts/<name>/CHANGELOG.md`, as it already did for `docs/conventions/<name>/`.
- `babysit-prs` counts an edit under `docs/contracts/instruction-exception-register/` or `docs/contracts/untrusted-content/` as a lane-source change, beside the `docs/conventions/` paths, which stay listed because installed plugin versions still read them.
