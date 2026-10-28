---
bump: patch
---

### Fixed

- pr-merge's Dependabot push check (`push_refusal` in `babysit_dependabot.py`) ties every commit on the pull request to the actor who pushed it, not only each push's tip ([#9006](https://github.com/melodic-software/claude-code-plugins/issues/9006)). Each commit a push brought (its `after` and the ancestors its `before` lacks, walked through the commits' parents) must be its pusher's own: a commit with Dependabot's author in a `dependabot[bot]` push, a github-actions[bot] commit in a github-actions[bot] push, and a lanes App commit in a lanes App push, else `pushed-by:<login>`. So a lanes App push can no longer carry a Dependabot-authored commit under an App tip. A commit that no push in reach brought refuses `push-history-incomplete`.
