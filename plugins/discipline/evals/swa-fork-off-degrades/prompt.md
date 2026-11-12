---
description: "Legacy sweep-all 9, its prompt behind the slash command (narration: a case can set only EVAL_ variables, so CLAUDE_CODE_FORK_SUBAGENT=0 is stated, not set). Stage 1b short-circuits on an explicit 0 before the canary, and the degrade path's first line is the exact token (reference/inheritance-preflight.md lines 37-41 and 115-135). first-line-token anchors the token at the reply's start, no-dispatch forbids any Agent call, zero-audits-stated needs no audits and no corrections said, digest-tiers the core, situational and never tiers, no-inline-correctors any corrector Skill call, no-corrector-body-read a Read of a corrector SKILL.md beyond its frontmatter. Pass --disallow-tools Grep if a run Greps the plugin dir."
tags: [discipline, sweep-all, outcome, narration, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "First line SWEEP-ALL: DEGRADED (fork-unavailable); no Agent call; no audits ran and no corrections were applied; then the posture digest."
---

/discipline:sweep-all full batch. (Assume CLAUDE_CODE_FORK_SUBAGENT is explicitly 0.)
