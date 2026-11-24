---
bump: minor
---

### Changed

- `CI Status`'s trust-gate hold clears for a Dependabot pull request whose one trust-gate path is `lib/cdn-pins/pins.json`, modified in place as the lanes App's CDN pins sync commit leaves it, once the lanes App's newest review-dependency round marker names the current head with `verdict=merge` (owner decision Q154 A). Until the verdict, the hold reads `#<n> by Dependabot changes only the CDN pins record on trust-gate paths`. `review-dependency-select` sends that hold to the model with `merge_clears_gate_hold: true` instead of skipping it as `gate-hold`, and the pr-unblock dispatcher re-runs the head's `CI Status` job after the verdict.
