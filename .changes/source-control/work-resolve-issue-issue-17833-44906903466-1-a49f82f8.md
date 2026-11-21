---
bump: patch
---

### Fixed

- `babysit-loop` and its evals say a `/loop` created on Claude Code 2.1.330 or later runs up to 30 days and an older one still ends at 7 days, where they said seven days for every loop. The restart-request handling on an expiry hit is unchanged ([#17833](https://github.com/melodic-software/claude-code-plugins/issues/17833)).
