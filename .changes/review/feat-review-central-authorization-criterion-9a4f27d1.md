---
bump: minor
---

### Added

- **`security-reviewer` flags opt-in authorization.** The A01 row of the OWASP floor now covers
  authorization that each route or handler must opt in to, with no central decision point and no
  default deny, even when every current route carries its check.
