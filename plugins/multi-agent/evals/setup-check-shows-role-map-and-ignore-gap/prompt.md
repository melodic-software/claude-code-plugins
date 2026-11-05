---
description: "Explicit check in a git repository with no multi-agent layer and no .gitignore. setup SKILL.md check: run the bundled scripts/setup.sh check, show one single/fanout line per role with the layer behind each value, the layers rows and notes, and the personal-override row, which is WARN here with the recommended .claude/**/*.local.* line; recommend the line, never edit .gitignore, modify nothing. ran-setup-check is a with-only indicator: the script ships only with the plugin. role-lines checks the line shape, not a value, so a host user layer cannot flip it. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['multi-agent', 'setup', 'check', 'read-only']
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs setup.sh check (never apply or --write), shows a single/fanout line for each of orchestrator, worker, verifier and retrieval, reports the personal-override WARN and recommends the .claude/**/*.local.* line without editing .gitignore; writes and edits nothing.'
---

/multi-agent:setup check
