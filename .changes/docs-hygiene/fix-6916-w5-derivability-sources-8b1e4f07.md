---
bump: patch
---

### Fixed

- `audit-derivability` no longer says every subagent other than `Explore` and `Plan` loads the
  launch-loaded files. Spot-tests still use `Explore` or `Plan`, now labeled as this skill's choice,
  and which types load those files is left to a links-only Sources record pointing at the sub-agents
  sections. The sweep model fallback is labeled as the skill's stand-in for `/multi-agent:route`
  ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
