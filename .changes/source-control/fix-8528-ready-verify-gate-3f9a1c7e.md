---
bump: patch
---

### Fixed

- `pull-request ready` refuses the flip unless the verify gate recorded `pass` (or a `--skip verify` record) for the head being flipped. The verify step records its result with the new `scripts/verify-gate.sh record`, and the flip's own shell command runs `verify-gate.sh check --head <sha>` before `gh pr ready`, so a failed gate or a commit after the gate can no longer be followed by the flip.
