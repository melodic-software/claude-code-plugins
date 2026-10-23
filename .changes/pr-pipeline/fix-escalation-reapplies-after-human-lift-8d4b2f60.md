---
bump: patch
---

### Fixed

- The pr-merge lane no longer adds `needs-human` back to a pull request after a person with write access removed it, while the escalation it explains is unchanged (same head and reasons). A removal by a bot lifts nothing, and a new head or new reasons escalate again ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane)).
