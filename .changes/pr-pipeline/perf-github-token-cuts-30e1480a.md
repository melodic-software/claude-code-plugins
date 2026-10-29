---
bump: patch
---

### Changed

- pr-verify runs its read-only resolver before its trigger gate, so a run the resolver skips (a
  head already judged or moved past, a draft, a run red for anything an approval does not lift,
  an author it does not judge) no longer spends the gate's reads. A judged run makes the same
  reads as before.
