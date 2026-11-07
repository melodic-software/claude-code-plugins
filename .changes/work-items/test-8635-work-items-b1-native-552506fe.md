---
bump: patch
---

### Changed

- The work-loop `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Twenty-seven new `wl-` cases cover the admission gate (hard gates, the in-flight check, the labeler precondition, the provenance and provenance-removal holds, body edit-time escalation), the objection window and who can object or answer, item text as data, the intake sweep's disclaimer and its never-admit rule, the adaptive cap and the rate-limit pause, account switches while paused, the no-progress stall, the drain exits and `--scope` lanes. Each is a described cycle graded on the reply. Legacy cases 6, 26, 27 and 28 were already covered by the `wl-` ports. Legacy cases 10, 12, 18 and 20 are held on #8635 for an owner decision on their graders.
