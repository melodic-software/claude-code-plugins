---
bump: patch
---

### Fixed

- `/debugging:debug`'s optional view and the rendered-view reference pass `""` for the `medium` option when it reads empty or unsubstituted and never put a `${user_config.*}` string in a shell command, and the held `builds-post-mortem-view-on-request` eval case is restored ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).
