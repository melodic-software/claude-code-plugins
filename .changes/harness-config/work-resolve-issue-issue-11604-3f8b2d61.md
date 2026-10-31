---
bump: patch
---

### Fixed

- `/harness-config:audit-permission-state` no longer reports the user settings file as the project scope when a session starts in the home directory outside a repository. When the project or local settings path is the user file, the reader marks that scope `not-applicable` and adds a note giving the reason. It reports the file once, under user, and raises no project-scope finding, such as `C2-autoMode` or `C2-defaultMode`, against keys that are legal in user settings.
