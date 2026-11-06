---
description: "Legacy check eval 1, skill-absent branch. /skill-quality:check check my-skill in an empty workspace: no .claude/skills and no my-skill. check SKILL.md Action: check step 1: when the resolved root does not exist, report it (and offer /skill-quality:setup); the checker itself prints 'Skill not found'. names-missing grades that the reply says the skill or root is missing; names-root grades that it names where it looked or how to point the checker (.claude/skills, skills_root, CHECK_SKILL_SKILLS_ROOT); no-fabricated-results judges that no PASS or per-check findings are invented; no-write and no-edit grade that my-skill is not created. Offering setup is optional, as the legacy case says. Needs --allow-tools Bash."
tags: [skill-quality, check, outcome, no-network]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply says my-skill (or the .claude/skills root that should hold it) was not found, names where the checker looked or how to point it at the right root, and reports no check results for a skill that does not exist."
---

/skill-quality:check check my-skill
