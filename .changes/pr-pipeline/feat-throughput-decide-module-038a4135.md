---
bump: minor
---

### Added

- `limits.lane-level` (`floor` 2, `ceiling` 4, `default` 3, `clean-windows` 2, `pools` `[lanes-app]`): the bounds and streak of the adaptive lane level L (owner decision Q111). `decide()` in `.github/scripts/lib/lane-level.mjs` picks L per window: up 1 after `clean-windows` clean windows with lane demand when every pool fits (peak share of its planned budget times (L+1)/L at most `api.<pool>.plan`), half on any limit signal the lanes App's own calls meet (a breaker trip is not one), never below `floor` or above `ceiling`; missing data holds L. A `floor` above the `ceiling` is rejected. Nothing reads L yet, so `SLOTS` stays 3.
