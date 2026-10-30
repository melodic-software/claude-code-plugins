---
bump: patch
---

### Fixed

- **babysit-prs:** a high path (a floor path, a configured denied path, or an aliasing path,
  symlink, submodule or mode change) no longer stops a pull request for the owner:
  `babysit_risk.PERSON_PREFIXES` drops `high-path:`, so `person_reasons` no longer names it and the
  merge gate adds no `needs-human` label for it. The path still holds the pull request. A
  trusted-actor widening, a listing past the files API's cap and a CRITICAL security finding still
  stop for the owner; an IMPORTANT security finding does not.
