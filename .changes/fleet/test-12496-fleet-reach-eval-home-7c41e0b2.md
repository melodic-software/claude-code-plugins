---
bump: patch
---

### Fixed

- The `reach` outcome evals can now produce a VALID pass. Their scaffold writes the fixture `FLEET.md` into the workspace and each prompt names that location, because the agent cannot see `$HOME` in a run: it expands `~` from the `/home/<user>` prefix of the paths in its context, and the run denies that read. The `not-a-key-problem` grader also accepts two observed correct wordings.
