---
description: "Narration: the user reports an unarmed guard in a fresh session. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 83-88: the guard registers from the hooks: block in the clean skill's frontmatter, not a plugin-level hooks/hooks.json (the plugin ships none); Claude Code arms it once /repo-hygiene:clean is invoked and keeps it armed for the rest of that session, so a session that never invoked the skill has no guard and nothing is wrong. Line 83: report it as INFO. no-hooks-manifest, frontmatter-hooks, armed-on-invocation and unarmed-info-expected grade that; no-fix-prescribed (llm) fails a reinstall, a settings edit or a hooks-manifest fix offered as the remedy. Bash is in allowed_tools because the SKILL.md pre-computed ghq line needs it to load. Needs --allow-tools Bash."
tags: [repo-hygiene, setup, outcome, check, guard, narration, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply says the plugin ships no plugin-level hooks manifest, the guard registers from the clean skill's frontmatter hooks and is armed once /repo-hygiene:clean is invoked and for the rest of that session, reports the unarmed fresh session as INFO and expected, and prescribes no reinstall, settings edit or manifest fix."
---

/repo-hygiene:setup check I opened a fresh session and the destructive guard does not appear to be armed. Is the hook broken?
