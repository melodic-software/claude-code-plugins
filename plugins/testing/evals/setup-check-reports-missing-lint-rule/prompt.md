---
description: "Explicit check in a git repository with one tracked pytest file and a ruff select of E, F and PLR0124. setup SKILL.md check: run the bundled skills/setup/scripts/setup.sh check and show its config, lint, instruction and hook-entry sections; a missing test-lint rule is a FINDING to report, not a neutral absence. Here the lint section prints PT011 as FINDING (F631 and PLR0124 present). It modifies nothing, never edits CLAUDE.md, AGENTS.md or a lint config, and installs no lint plugin. ran-setup-check is a with-only indicator: the script ships only with the plugin. No grader depends on whether node is on the host. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['testing', 'setup', 'check', 'read-only']
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs setup.sh check (never apply), reports ruff PT011 as a missing rule (FINDING) for the Python tests, and offers the instruction line without pasting it; writes and edits nothing.'
---

/testing:setup check
