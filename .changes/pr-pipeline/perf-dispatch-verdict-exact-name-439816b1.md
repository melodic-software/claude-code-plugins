---
bump: patch
---

### Changed

- The address-feedback and pr-unblock dispatchers' FAIL-cap reads (`verify-cap.mjs`) no longer
  look for the artifact listing pr-merge's last run saved. The verdict reader reads the FAIL
  index by exact name, so no gate saves a listing to carry, and the search cost one run listing
  and ten runs' artifact listings a job for nothing. The run cache and head-ref map are still
  carried on the first FAIL-cap read; `BABYSIT_VERIFY_LISTING_CARRY` is gone from both dispatch
  steps.
