---
bump: patch
---

### Changed

- The `setup` skill no longer says `apply` writes only `docs/conventions/education.yaml`: on an
  explicit yes it also writes the convention-home region and the `.gitignore` line, as its step 5
  and the script already did. `quiz-me` points at the setup routes and the plugin-reconfiguration
  convention instead of restating a CLI form. No behavior change.
