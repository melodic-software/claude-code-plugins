---
bump: patch
---

### Added

- The three `reach` outcome eval cases seed a fixture `~/.config/fleet/FLEET.md` through `context.scaffold_script` when a run passes `--scaffold` ([#8550](https://github.com/melodic-software/claude-code-plugins/issues/8550)), so the skill's first step finds a manifest. The fixture names only made-up hosts and accounts, and its script refuses to run against the account's real home or to overwrite a file.
