---
bump: patch
---

### Fixed

- The interview page's Activity panel lists under "Needs you" only what needs the user's input: a restatement to confirm, the finish, and a question that still waits on their answer. Added questions, recommendation revisions and saved Notes replies move to the log, so they no longer raise the Activity badge, the notice, the toast or the hidden-tab title count. `round.py` marks a `revise` entry `revised` and a `reply` or `wait` entry `waits` ([#7751](https://github.com/melodic-software/claude-code-plugins/issues/7751)).
