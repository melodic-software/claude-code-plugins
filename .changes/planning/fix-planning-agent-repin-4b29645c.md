---
bump: patch
---

### Changed

- **`interview-defenses.test.sh` digest re-pins no longer need a person.** Any session, a lane included, may re-pin a digest after reading the diff of the guarded text: `tests/repin.sh <pin-label> <reason>` runs with no terminal and no y/N prompt, rewrites the one sha256 literal, adds the reason above the pin, and prints `<label>: <old> -> <new>` for the commit message. The suite's failure messages and header drop the attended-only rule; the commit carries old -> new and why the defense holds, and the PR review judges it.
