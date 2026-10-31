---
bump: minor
---

### Removed

- The `design.concern_spoke_cap` setting. `/user-interface:design` now reads every concern spoke whose `read_when` holds in one pass instead of stopping at two and listing the rest as next steps. No observed failure backed the cap. A team or local file that still sets it gets an unknown-key error for `design`, and the rest of the file still loads.
