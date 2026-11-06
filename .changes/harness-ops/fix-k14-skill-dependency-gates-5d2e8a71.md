---
bump: patch
---

### Fixed

- gate audit-plugin-landscape's docs reads on the discovery plugin

  Step 3 reads pages through /discovery:read-docs or /discovery:research
  only when the discovery plugin is installed; otherwise it uses
  WebFetch and says so.
