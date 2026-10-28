---
bump: patch
---

### Fixed

- `/user-interface:design` reads an `account_tools_enabled` value that arrives as its unexpanded `${user_config.account_tools_enabled}` token as the key's default `true`, so account-bound tools stay enabled instead of being read as off.
