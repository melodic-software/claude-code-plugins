---
bump: patch
---

### Fixed

- The `code-reviewer`, `brief-reviewer`, `ci-log-auditor`, `doc-drift-detector` and
  `architecture-guardian` agents no longer claim their `model: opus` pin always reviews on a model
  at least as capable as the one that produced the work: that holds for Opus-family and
  lower-tier sessions, and a more capable session is reviewed one tier down to keep judgment
  fan-out off the frontier tier. Each points at the subagent model order. The pins are unchanged.
  `fanout` run-everything mode points at the values the Agent `model` parameter takes and labels
  the cross-vendor reviewer as this repository's design choice, and `quality-gate` downstream mode
  points at the subagent nesting rule ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
