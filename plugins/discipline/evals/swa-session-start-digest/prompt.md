---
description: "Fired at conversation start with no work yet, the sweep takes the cheap posture-digest path: it reports the core, situational and never tiers from metadata, states that nothing was audited, and dispatches no fork. no-corrector-body-read fails a Read of a corrector's SKILL.md without a limit of 40 lines or fewer, since the digest reads tier metadata and loads no corrector body (SKILL.md lines 22-27)"
tags: [discipline, sweep-all, outcome]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "No Agent call; the reply reports the core, situational and never-batched tiers and says no audit ran (digest only); no corrector SKILL.md is read past its frontmatter."
---

/discipline:sweep-all set our posture before we start
