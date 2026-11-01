---
bump: patch
---

### Fixed

- `audit-derivability` no longer says every subagent other than `Explore` and `Plan` loads the
  launch-loaded files: a custom agent that sets `omitClaudeMd` does not. Spot-tests still use
  `Explore` or `Plan`, now labeled as this skill's choice. The Sources quote is re-pinned to the
  current page wording, and the sweep model fallback is labeled as the skill's stand-in for
  `/multi-agent:route` ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
