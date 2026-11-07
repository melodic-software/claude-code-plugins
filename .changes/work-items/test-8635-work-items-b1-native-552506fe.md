---
bump: patch
---

### Changed

- The work-loop `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Thirty-one new `wl-` cases cover the admission gate (hard gates, the in-flight check and its age bound, the labeler precondition, the provenance and provenance-removal holds, body edit-time escalation), the objection window and who can object or answer, item text as data, the intake sweep's disclaimer and its never-admit rule, the adaptive cap and the rate-limit pause, account switches while paused, the no-progress stall, the drain exits, `--scope` lanes and `--single-pass`. Each is a described cycle graded on the reply. Legacy cases 6, 26, 27 and 28 were already covered by the `wl-` ports.
