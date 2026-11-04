---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` documents that no workflow names `BABYSIT_VERIFY_LISTING_CARRY`
  now that index mode saves no listing to carry; the reader still takes one when named. The
  floor-path pins drop the removed `listing-carry.mjs` row.
