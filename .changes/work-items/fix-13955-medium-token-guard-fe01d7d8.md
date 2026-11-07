---
bump: patch
---

### Fixed

- `/work-items:morning-brief` and `/work-items:triage` pass `""` for the `medium` option when it reads empty or unsubstituted and never put a `${user_config.*}` string in a shell command ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
