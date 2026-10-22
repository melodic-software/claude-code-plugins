---
bump: patch
---

### Fixed

- **`continue-in-background --cloud` falls back to a local background session when the CLI refuses the cloud launch for lack of a terminal** ([#8792](https://github.com/melodic-software/claude-code-plugins/issues/8792)). Before, a refused launch ended with the `/clear`-then-paste instruction, which stalled a run meant to continue while the user was away. The goal probe record now holds the refused-launch probe and still marks cloud goal arming as unprobed.
