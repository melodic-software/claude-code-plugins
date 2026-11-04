---
bump: patch
---

### Changed

- No workflow looks for the artifact listing pr-merge's last run saved any more. The verdict
  reader reads the FAIL index by exact name, so no gate saves a listing, and each search cost
  one run listing and up to ten runs' artifact listings for nothing. The address-feedback and
  pr-unblock dispatchers' FAIL-cap reads (`verify-cap.mjs`), pr-merge's `merge` and
  `enable-auto-merge` jobs, and ci-status's merge-queue reader no longer run it; the run cache
  and head-ref map are still carried. `BABYSIT_VERIFY_LISTING_CARRY` is gone from every job.

### Removed

- `.github/scripts/pr-merge/listing-carry.mjs` and its floor row, and pr-merge's
  `pr-merge-verify-listing` upload with its credential scan.
