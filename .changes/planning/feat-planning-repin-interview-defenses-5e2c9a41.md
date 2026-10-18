---
bump: minor
---

### Added

- `tests/repin.sh <pin-label> <justification>` re-pins one digest pin of `interview-defenses.test.sh` in one attended command: it rewrites only that pin's sha256, adds the justification comment above the pin, reruns the test and prints PASS or FAIL. It refuses an unknown or ambiguous label and changes nothing when the digest already matches. The test's attended-only message names it.
