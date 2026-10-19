---
bump: patch
---

### Fixed

- The session bridge's channel policy reader now reads the macOS managed preferences and the Windows HKLM registry policy, falls back to the loopback transport when one exists but cannot be read, and combines lists and merges nested blocks across managed-settings drop-ins.
