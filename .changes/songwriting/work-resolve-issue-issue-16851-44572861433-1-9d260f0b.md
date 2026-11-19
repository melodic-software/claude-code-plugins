---
bump: patch
---

### Changed

- `object-writing` drops the recheck trigger from its model-pricing pointer. The fleet-tier rule
  compares rates read live from that section, so the pointer needs no trigger under the
  upstream-drift contract.
