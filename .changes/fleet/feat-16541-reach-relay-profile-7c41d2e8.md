---
bump: minor
---

### Added

- The reach skill starts a relay turn or session in a WSL lane in the plugin profile the task names: it finds the target's `profiles.mjs` through `claude plugin list --json`, runs `launch --unattended` there with the relay's own settings in `--with`, and starts `claude` with the printed command. With no profile named, no plugin-profiles on the target, or a Windows lane, it starts as before and says the profile was not applied.
- The reach skill's prompt line says to name the session that holds a PR, issue or branch in the prompt, and never to tell the target to take the work over on its own judgment.
