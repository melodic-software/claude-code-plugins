---
bump: minor
---

### Changed

- `/adhd:clarify` resolves the `rendered-views` `medium` before it picks a rung, from a
  `--medium` argument, then `~/.claude/rendered-views.md`, the team `.claude/rendered-views.md`
  and an untracked, gitignored `.claude/rendered-views.local.md`. `terminal` or `file` from any
  layer keeps the decision table local, even with the Artifact tool present. `artifact` (or
  `hosted`, read as `artifact`) publishes only from the argument, the user-global layer or that
  overlay; a team-layer publishing value keeps the page in a local file. With no layer set, the
  shipped ladder is unchanged, and the output names the layer that decided or "shipped default".
