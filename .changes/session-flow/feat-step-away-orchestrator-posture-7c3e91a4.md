---
bump: minor
---

### Added

- `step-away` can run an absence as an orchestrator: with the new `away_orchestrate` option on, or launch words that ask for it, the main session arms `/session-flow:orchestrate`, delegates work and keeps only briefs, verdicts and state in its own context, so it lasts through compaction. Model, effort and outside vendors come from `/multi-agent:route` when that plugin is on; delegated work follows the away rules. The Stop and UserPromptSubmit notes name the posture so it returns after compaction.
- `step-away` reads the context zone before arming and, when it is heavy, offers a fresh session in the launch question.
