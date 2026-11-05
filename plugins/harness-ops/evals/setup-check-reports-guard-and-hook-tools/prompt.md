---
description: "Explicit check in a git repository with no hook log root. setup SKILL.md check: read the rendered userConfig values, never a settings file; report a PASS/FAIL/INFO table covering the registry and skill-usage destinations, the hook log root guard (absent here, so INFO with logging off or FAIL with logging on), the retired-convention check run through the bundled lib/check-retirements.sh --manifest retirements.yaml (exit 0 here, PASS), and node and jq rows probed through Bash; modify nothing. ran-retirements-check is a with-only indicator: the script and manifest ship only with the plugin. No grader depends on whether node or jq is on the host or which logging value the host renders. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded, unlike the model-invoked plugins-audit case. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['harness-ops', 'setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check-retirements.sh with the plugin manifest and reports a PASS/FAIL/INFO table with node, jq and hook log guard rows; reads no settings file; writes and edits nothing, the guard included.'
---

/harness-ops:setup check
