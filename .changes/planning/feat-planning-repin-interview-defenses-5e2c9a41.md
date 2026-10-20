---
bump: minor
---

### Added

- `tests/repin.sh <pin-label> <justification>` re-pins one digest pin of `interview-defenses.test.sh` in one attended command: it rewrites only that pin's sha256, adds the justification comment above the pin, reruns the test and prints PASS or FAIL. It refuses an unknown or ambiguous label and changes nothing when the digest already matches. It writes only when stdin and stdout are both terminals and the person answers y after seeing the old and new digest and the plugin's `git diff --stat`; any other run exits non-zero and writes nothing. The test's attended-only message names it.
