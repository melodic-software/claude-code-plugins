---
bump: major
---

### Removed

- /review:ratchet leaves the review plugin. It is now `/toolchain:ratchet` in the toolchain plugin, with the same behavior; install toolchain to keep using it. The `ratchet_offer` setting stays here, and the offer in `/review:audit-enforceability` stubs now names `/toolchain:ratchet`.
