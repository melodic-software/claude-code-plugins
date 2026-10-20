---
bump: patch
---

### Fixed

- The interview page's Activity panel lists under "Needs you" only what needs the user's input: a restatement to confirm, the finish, a Notes reply that asks them something, and a question that still waits on their answer. Added questions, recommendation revisions and other Notes replies move to the log, so they no longer raise the Activity badge, the notice, the toast or the hidden-tab title count. `round.py` marks a `revise` entry `revised`, a `reply` or `wait` entry `waits`, and a `note-reply` sent with `needsAnswer` `asks` ([#7751](https://github.com/melodic-software/claude-code-plugins/issues/7751)).
