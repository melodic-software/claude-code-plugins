---
bump: patch
---

### Fixed

- `/prototype:explore-directions` now says the level report line (`level: <name> (<layer>)`) is still printed when the request says to build without asking or no plan is shown, before the run's first tool call that writes a file ([#16467](https://github.com/melodic-software/claude-code-plugins/issues/16467)).
- The `ed-controls-everything-default` eval's `runtime-inlined` grader now passes a page written by a redirect to a shell variable, such as `{ cat ...; } > "$OUT"`, and its samples include one of that shape ([#16467](https://github.com/melodic-software/claude-code-plugins/issues/16467)).
