---
bump: minor
---

### Added

- `fanout_act_on_cap` sets how many rows under each `## By axis` heading of a `/review:fanout` report are marked act on. Under `### Spec` and `### Standards`, each counted on its own, the first that many rows get `yes` in a new last `Act on` cell and every later row gets `no`; no row leaves the report. It is set per user through the plugin option and per repository in `docs/conventions/review.yaml`, resolved like `fanout_diversity`. The default is `2`: in the two-defect fixtures both planted defects sat at positions 1 and 2 under one heading in 12 of 12 runs, so a cap of `1` would have dropped the second each time (#12505).
