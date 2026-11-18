---
bump: patch
---

### Fixed

- A second `/plugin-profile`, with or without a profile name, while the picker pane is open is refused with a line saying a pick is already open, so it can no longer start a second switch; the open pane's pick still completes. A pick in the pane is refused when a switch from before is still waiting for its reload, and the picker reads whether its pane is open from Claude Code, so a reload of the plugin while the pane is up no longer loses track of it ([#16816](https://github.com/melodic-software/claude-code-plugins/issues/16816)).
