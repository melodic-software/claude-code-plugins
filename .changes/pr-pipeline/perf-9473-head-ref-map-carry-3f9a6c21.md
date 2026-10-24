---
bump: patch
---

### Changed

- pr-merge's head-ref map (`.github/scripts/pr-merge/head-ref-map.mjs`) is carried on a run that saves no artifact listing, such as a run with no candidates: the map read before the gate is uploaded as it is, with one log line and no warning, and the next run that saves a listing prunes it. Before, that run warned and uploaded no map, so once the trusted-run window passed the next run downloaded every untied FAIL again. A listing file that exists but cannot be read still uploads nothing, and with no map read before the gate nothing is uploaded. The map is still read only from the newest scheduled or hand-started `pr-merge.yml` run on main and never passes through `actions/cache`.
