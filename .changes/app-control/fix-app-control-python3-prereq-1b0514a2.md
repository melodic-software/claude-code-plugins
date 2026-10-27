---
bump: patch
---

### Fixed

- `/app-control:drive` names how to get `python3` for the integrated-app pin check: app-control now declares it in `prerequisites.json`, and drive runs the bundled checker for the install command when it is missing.
