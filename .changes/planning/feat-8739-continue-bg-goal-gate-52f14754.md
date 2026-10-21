---
bump: patch
---

### Changed

- **`draft-goal-condition`'s mutation gate accepts a background-launch request as approval** ([#8739](https://github.com/melodic-software/claude-code-plugins/issues/8739)). When the person, shown a condition, explicitly asks `/session-flow:continue-in-background` to launch with it, that request is their approval to arm it as the launched session's `/goal`.
