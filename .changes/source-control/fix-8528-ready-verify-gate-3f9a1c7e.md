---
bump: patch
---

### Fixed

- `pull-request ready` refuses the flip unless the head being flipped has a recorded `pass`, or `skipped` when `--skip verify` or `pre_ready` turned the gate off, and a recorded `fail` or a commit after the record also refuses it. The result is recorded in every run with the new `scripts/verify-gate.sh record`, taking `pass` or `fail` from the gate's exit status, and the flip's own shell command runs `verify-gate.sh check --head <sha>` before `gh pr ready`.
