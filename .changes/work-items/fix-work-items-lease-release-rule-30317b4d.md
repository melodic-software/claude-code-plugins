---
bump: patch
---

### Fixed

- The GitHub adapter's `release` and `renew-lease` accept the holder's live lease while a newer lease that has not yet backed off is on the item, and refuse a lease an earlier live lease outranks. They use the rule claim arbitration uses (earliest live lease holds, a completed run's lease counts as released), now one shared `wit_lease_winner` function. Before, a holder's release under such a lease was refused and its lease blocked every later claim until its TTL.
- `release` now hands the assignee back itself: it removes the login unless another live lease held by that login remains, so one same-login session's hand-back no longer unassigns another session's live claim. `/work-items:attend-queue`, `/work-items:triage` and `/work-items:work` rely on it and no longer clear `@me` themselves; attend-queue releases right after the flip.
- A same-login `claim` that loses arbitration keeps `@me` only when the login was assigned before the claim, so it no longer leaves an assignee behind that no lease holds. A winning claim puts its assignee back if a same-login release removed it, and a default claim that fails after posting its lease supersedes that lease, as a lease-only claim already did.
