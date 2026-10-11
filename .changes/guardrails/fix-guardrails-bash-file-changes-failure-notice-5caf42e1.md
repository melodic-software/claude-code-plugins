---
bump: patch
---

### Fixed

- **`check-bash-file-changes` exited silently on an unexpected error.** It now gives the notice the shell hooks' abort boundary gives a fail-open hook, "guardrails check-bash-file-changes: guard did not run (internal error, rc=1); this call was not checked", on stderr and as a `systemMessage`, and still exits 0. A normal run stays quiet ([#6905](https://github.com/melodic-software/claude-code-plugins/issues/6905)).
