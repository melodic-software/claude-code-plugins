---
bump: minor
---

### Changed

- `/planning:plan` no longer dispatches the fresh-context `plan-reviewer` on LOW plans. Under the default `plan_stress_test: auto` it runs when the blast radius is MEDIUM or higher, a stress-test trigger matches, or the user asks for a review; a before/after eval on LOW plans measured a change of -0.03 (95% interval -0.08 to +0.03) with no case drop, and MEDIUM keeps the reviewer until it is measured; the blast radius is now assessed before that decision, and the Step 5 presentation states a skip and its reason (`Reviewer: skipped (blast radius LOW, no trigger)`). `plan_stress_test` `reviewer` and `both` and verification `strict` still always run it; `light` and `off` still skip it. Basis: Anthropic's [Prompting Claude Opus 5, "Task scope and over-verification"](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#task-scope-and-over-verification): explicit verification steps and "use a subagent to verify" cause over-verification, and removing them reduces wasted tokens with no loss in quality.
- New eval case `plan-low-risk-skips-reviewer`: a LOW blast-radius draft with default settings dispatches no plan-reviewer and reports the skip line.
