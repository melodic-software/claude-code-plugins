---
bump: minor
---

### Changed

- No path is held for being trusted alone (owner direction 2026-10-24): ci-status's `merge-holds.mjs` drops `HOLD_PATH_FLOOR` and the forced denied paths (the pipeline config and the trusted-actor list), and resolve-config no longer adds them to `merge.diff-check.denied-paths`. This repository sets `high-path-floor: false`. The trusted-actor widening hold and the review lanes still judge those paths.
- ci-status no longer holds a plugin or marketplace manifest change; the security lane flags it.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a cost path; the infrastructure-as-code cost paths stay.
- A body hold (`Hold:` or "do not merge") counts only when a person wrote or edited the body, not the lanes App's own text.
- The verifier pass binds a link of no issue or of several: only a link that drops the judged issue holds it.
