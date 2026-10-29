---
bump: patch
---

### Fixed

- An own answer on the interview page replaces the recommendation, so it no longer carries the recommendation's commitments. Confirm's "Tick these and confirm" list leaves them out, the question's pane labels them "replaced by your own answer", and the Brief names none of them, even one ticked before the own answer. Before, Confirm ticked a commitment the own answer had replaced, and the Brief listed it as confirmed beside a decision that contradicted it. The ledger row still keeps those ticks, so an import restores them.
- `round.sh status` now lists a hedged question's unticked commitments on a `hedged, to confirm:` line, so it names the same commitments as the page's To confirm list.
