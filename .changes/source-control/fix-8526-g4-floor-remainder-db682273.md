---
bump: patch
---

### Changed

- The babysit merge gate's high-path floor now also holds plugin git hooks (`plugins/*/git-hooks/**`), any `scripts/` directory at any depth under `plugins/`, and two skill-run scripts outside one (`net-probe.sh`, `preflight.mjs`) out of unattended merge.
