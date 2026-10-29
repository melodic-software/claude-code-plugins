---
bump: minor
---

### Added

- `limits.api` github-token `pace` (default 0.2, in rate-limits.json): the lost-run reconciler
  and pr-unblock-dispatch skip every other scheduled tick (the even run numbers) while the
  GITHUB_TOKEN pool's remaining at its reset, projected from the window's burn rate so far, is
  under that share of the header's limit, so the timer lanes slow to half cadence before the
  breaker stops every lane. Any other event, or a failed read, runs as before.

### Changed

- pr-verify runs its read-only resolver before its trigger gate, so a run the resolver skips (a
  head already judged or moved past, a draft, a run red for anything an approval does not lift,
  an author it does not judge) no longer spends the gate's reads. A judged run makes the same
  reads as before.
