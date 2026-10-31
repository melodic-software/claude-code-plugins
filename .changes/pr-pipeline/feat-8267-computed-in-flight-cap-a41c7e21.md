---
bump: minor
---

### Changed

- `merge.max-in-flight` is computed: `merge.in-flight-sizing` records the measured peak merge rate,
  time in flight and lanes App spend beside the formula, `scripts/compute-max-in-flight.py` prints
  the value, and a test fails any other. The measured day computes 11.
