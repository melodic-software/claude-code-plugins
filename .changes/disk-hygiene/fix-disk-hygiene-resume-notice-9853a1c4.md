---
bump: patch
---

### Fixed

- **A session resumed after `/disk-hygiene:clean` now hears that the clean skill's guard is gone.** The skill-frontmatter belt (the PowerShell deletion prompts and the deny-by-default Bash lane) is not registered after `claude -p --resume`, so an approved manual-lane delete ran unprompted in the resumed process. The `/disk-hygiene:clean` expansion hook now writes a per-session marker, and the existing `SessionStart` entry, on `source: resume` with that marker present, tells the model to make no delete or overwrite until the user types `/disk-hygiene:clean` again. It is a notice, not a gate. The safety model, the unsupported-platform handoff, the README and the setup skill now state the belt's lifetime as the process that invoked the skill, with the Windows probe as the verification record ([#9853](https://github.com/melodic-software/claude-code-plugins/issues/9853)).
