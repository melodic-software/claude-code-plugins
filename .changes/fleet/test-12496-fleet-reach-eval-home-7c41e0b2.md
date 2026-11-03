---
bump: patch
---

### Changed

- The `reach` skill body is shorter (235 to 220 lines) with the same routes, commands, pointers and safety rules: the Purpose section folds into "Resolve the target first", which now comes before the route matrix, and repeated pointers to `reference/relay.md` merge into one. Measured on the three outcome cases: non-inferior to the previous body on Sonnet 5.5 and Opus 5.5 with no case drop.

### Fixed

- The `reach` outcome evals can now produce a VALID pass. Their scaffold writes the fixture `FLEET.md` into the workspace and each prompt names that location, because the agent cannot see `$HOME` in a run: it expands `~` from the `/home/<user>` prefix of the paths in its context, and the run denies that read. `fr-decline-ssh-allow-rule` also gets a workspace settings file, and five regex graders now match their cases' expected outcomes.
