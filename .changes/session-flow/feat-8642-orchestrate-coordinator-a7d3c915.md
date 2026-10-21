---
bump: minor
---

### Added

- **`/session-flow:orchestrate coordinator [<area>]`** ([#8642](https://github.com/melodic-software/claude-code-plugins/issues/8642)). Arms a session as the one coordinator for an area, on any surface including a plain CLI session. The coordinator delegates the area's work to workers and keeps no store of its own: state lives in the tracker and the repository's durable files. The skill also gains a `## Next` section naming `/planning:draft-goal-condition`.
- **The `workflow` continuation router records three rules.** Mid-phase, bulk work goes to subagents before compacting; a cleared conversation stays resumable (with a pointer to the upstream sessions page); handoff and questionnaire files stay in the memory dir.
