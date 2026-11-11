---
description: "Legacy setup eval 2. /skill-quality:setup check with skills_root unset and two scaffolded skills under packages/agent/skills: setup verifies that root without a confirmation gate and routes the persistent skills_root change through Claude Code. setup SKILL.md check steps 1-2 and 'Reconfiguration guidance': set skills_root through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated; never uninstall to reconfigure; rerun check in a fresh session; never write user settings or pluginConfigs. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-reconfiguration contract the skill points at, and install-config-fallback and scope-from-plugin-list grade them there; a with-plugin run that cannot reach the contract fails them. counts-two-skills grades a count of 2 tied to packages/agent/skills on the same line (the path alone is the prompt's own words, and a bare 'rung 2' is not a count); no-ask grades that no confirmation is asked; configure-route, values-skills-root, names-reconfiguration-convention and fresh-session each grade one requirement; routes-through-claude-code judges the whole route, no uninstall, and that neither settings nor the CHECK_SKILL_SKILLS_ROOT override is persisted (explaining the one-run override is optional); no-write and no-edit grade that nothing is written. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --scaffold."
tags: [skill-quality, setup, check, outcome, scaffold, read-only, no-network]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
expected_outcome: "The reply verifies packages/agent/skills holds 2 skills, without asking first, and routes the persistent skills_root change through Claude Code's native configure flow for skill-quality@<marketplace> with skills_root set to packages/agent/skills, pointing at the plugin-reconfiguration convention for the headless routes; never uninstall to reconfigure; then rerun check in a fresh session. It writes nothing."
---

/skill-quality:setup check

Our skills live under packages/agent/skills.
