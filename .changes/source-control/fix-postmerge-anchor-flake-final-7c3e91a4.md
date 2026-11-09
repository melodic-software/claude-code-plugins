---
bump: patch
---

### Fixed

- let a re-run flake stop holding the post-merge anchor

  A full run whose identity re-run passed (a flake) kept its merge from
  ever reading final, so the lane's floor anchor stopped there and every
  pr-merge check re-read every merge after it. Such a flake now counts as
  final once `merge.quarantine-days` have passed since the run and no open
  demotion record names it. A flake read through a newer run superseding
  it still never counts as final.
