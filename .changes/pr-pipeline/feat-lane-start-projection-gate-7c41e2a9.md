---
bump: minor
---

### Added

- The issue lane's start gate (`check-kill-switch`, new input `project`, set only on the read runner's first call) also holds a run while the pacer's projection of the GITHUB_TOKEN window's burn rate to `start-run-minutes` ahead (21, rate-limits.json), or to the reset when sooner, leaves under 1 - `plan` (0.3) of the header's limit. The hold is a `budget` stop with the window's reset, so work-unblock's sweep re-fires it after the reset; its notice names the projected share, the horizon and the threshold. The 10% `start-gate` share and the brake stay as they are. The projection lives in `.github/actions/check-kill-switch/projection.mjs`, which `pace.mjs` now uses too.
- `pace-pr-merge` (0.3, rate-limits.json alone) replaces `pace` for pr-merge, so its scheduled merge and enable-auto-merge sweeps skip every other tick once the window is projected to pass the `plan` share, before the other timer lanes slow down. `pace` 0 still turns all pacing off.
