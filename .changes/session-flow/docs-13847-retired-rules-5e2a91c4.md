---
bump: patch
---

### Changed

- The handoff reference docs describe `## Retired rules` (a rule or promoted preference leaving the hot file is listed in this hop's file with a reason, and a rule never leaves to meet the size cap) and the core, carried and written sizes `validate` reports, including the UNVALIDATED pass when the core plus carried part alone is over the cap (#13847).
