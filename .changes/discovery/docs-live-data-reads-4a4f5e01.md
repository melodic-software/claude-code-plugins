---
bump: patch
---

### Fixed

- Explore no longer probes MCP servers or other live systems, matching its description. The stage that needs a live system's current state reads it directly through the system's CLI or MCP tool.
