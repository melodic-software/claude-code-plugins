---
bump: patch
---

### Fixed

- The interview, plan, PRD and design skills state each settings token once with an inline fallback ("unexpanded or empty means off") and refer to the setting afterwards, so an unexpanded token is no longer read as a true condition.
