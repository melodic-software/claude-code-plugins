---
bump: patch
---

### Fixed

- `/review:security-review` rates a finding CRITICAL (the one severity that holds a pull request for a person) only when it shows who reaches the change, what security impact they get, and that no existing control stops it, each with file and line.
  - Touching a trust control, a gate file or a hold path no longer counts as a severity by itself.
  - A widening of who is trusted, of what a token may do, of untrusted reach or of the kill switch still meets the bar by itself, unless a cited control blocks it.
  - A weakened merge hold, such as one that guards only spend, has to show a security impact like any other finding.
  - A finding that rests on a configuration value quotes the line it read. A marketplace entry with `"defaultEnabled": false` is therefore read as opt-in (IMPORTANT), not default-on.
  - Every CRITICAL candidate now gets a refute pass that looks for a blocking control.
  - A finding the review cannot settle stays CRITICAL.
