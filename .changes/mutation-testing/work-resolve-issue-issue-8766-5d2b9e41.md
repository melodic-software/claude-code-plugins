---
bump: minor
---

### Added

- **The user config layer is `userConfig`** ([#8766](https://github.com/melodic-software/claude-code-plugins/issues/8766)). The plugin declares two options that mean the same thing in every repository, `operators` and `max_mutants`, and the config cascade reads them as its lowest layer in place of the retired `~/.claude/mutation-testing.md` file. A team or local file overrides them. The audit's `Config:` line names `userConfig` as the source of each value it supplies. Tool, diff target, mutate paths and test command stay per repository and never come from `userConfig`.
- **`setup apply` takes a target layer**: `team` (the default), `local` or `user`. `local` writes the untracked `.claude/mutation-testing.local.md` overlay with only the keys the user overrides, plus the `.gitignore` line when the user accepts it. `user` writes nothing: it settles the two options, names `/plugin configure mutation-testing@<marketplace>` to save them, runs no test command, and leaves `git status` unchanged. New eval cases cover a user-layer-only audit and `apply user`.

### Fixed

- **`setup check` runs no unconfirmed test command.** With no configured `test-command`, the baseline probe asks for the command or waits for the user to confirm a proposed one, and an unattended run reports the probe as not run.
