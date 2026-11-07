---
bump: none
---

No release needed (test): the `fix-light-skips-semantic-diff` eval case is tagged `no-network`, since its only grader reads the skip token and needs no fetched contract, so the skill's live detector-findings contract read in the eval sandbox no longer invalidates a run.
