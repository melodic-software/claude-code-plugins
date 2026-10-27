---
bump: patch
---

### Fixed

- `/review:security-review` rates a finding CRITICAL, the one severity that holds a pull request for a person, only when it shows who reaches the change, what security impact they get, and that no existing control stops it, each with file and line. Touching a trust control, gate file or hold path is no longer a severity by itself; a widening of one still is, unless a cited control blocks it. A finding that rests on a configuration value quotes the line it read, so a marketplace entry with `"defaultEnabled": false` is read as opt-in (IMPORTANT), not default-on. Every CRITICAL candidate now gets a refute pass that looks for a blocking control, and an unsettled finding stays CRITICAL.
