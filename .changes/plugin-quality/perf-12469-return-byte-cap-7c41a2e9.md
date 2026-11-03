---
bump: patch
---

### Changed

- The return contract (`/plugin-quality:report`) caps a dispatched agent's whole final message at 4,096 bytes; detail that does not fit goes in the agent's artifact.
