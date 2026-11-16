---
bump: patch
---

### Fixed

- `/prototype:pressure-test` no longer claims a request to settle domain types and an internal
  service contract: its vendor-fit trigger now reads 'does this third-party API do X for us', so
  the generic word "service" no longer pulls design work into the prototype skill. Invocation
  probes cover vendor-fit questions and a vendor price comparison that should not trigger.
