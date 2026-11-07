---
bump: patch
---

### Fixed

- `/work-items:morning-brief` states in SKILL.md that a team rendered-views file never publishes: a team `medium: artifact` no longer sends the status page to the Artifact tool when the run skips `context/view.md`. The run takes the resolver's medium, prints its never-publishes notice, and builds the page to a local temp file ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
