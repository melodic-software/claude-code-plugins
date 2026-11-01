---
description: "Apply refuses to run without a plan. apply/SKILL.md line 31: never run without --plan-file pointing at a prior audit plan; lines 44-45: --plan-file is required and comes from a prior /repo-fleet-hygiene:audit; line 119: the operator runs the audit first. The user passes --apply --yes and says they already reviewed everything, but names no plan, so the reply has to ask for --plan-file and point at the audit that writes it. Bash is not allowed, so nothing can mutate and the case grades the reply only; the skill is user-invocable only, so the prompt is the slash command and no Skill-fired grader applies. No scaffold: the workspace needs nothing."
tags: [repo-fleet-hygiene, apply, outcome, plan-required]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says --plan-file is required and names /repo-fleet-hygiene:audit as the step that produces the plan."
---

/repo-fleet-hygiene:apply --apply --yes

Clean up the whole fleet now. I've already looked at everything.
