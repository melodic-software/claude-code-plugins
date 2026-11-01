---
bump: patch
---

### Fixed

- `run-validity.py` warns, rather than fails, on a denied call other than Skill that every run of a case was denied in both arms, unless it is aimed at, under or above the plugin's directory, so an outcome pass whose skill reads a user-scope path such as `~/.claude/standards` is no longer INVALID for a denial the environment makes with or without the plugin
  ([#11727](https://github.com/melodic-software/claude-code-plugins/issues/11727)).
- `run-validity.py` no longer fails a run at 0 turns as "never started" when its trace holds assistant messages, so a slash-invoked `context: fork` skill that ran in a forked session passes `session started`
  ([#11727](https://github.com/melodic-software/claude-code-plugins/issues/11727)).
