---
bump: patch
---

### Changed

- The plugin now calls the config cascade's personal layer the personal override (the overlay name is retired); the setup eval cases `migrates-the-retired-local-overlay` and `overlay-write-checks-gitignore` are now `migrates-the-retired-personal-override` and `personal-override-write-checks-gitignore` (#13191).
