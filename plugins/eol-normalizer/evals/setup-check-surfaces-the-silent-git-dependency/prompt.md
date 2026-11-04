---
description: "Explicit check in a git repository with an eol=lf rule. setup SKILL.md: check reads the entry script and the sourced normalize-eol.sh library, reports a PASS/FAIL/INFO table, says a missing git emits no notice so the probe is the only visibility, confirms registration through /plugin Installed, and modifies nothing. status-table needs jq, git and node rows; node is a current check row the legacy expectation predates. read-sourced-library is a with-only indicator: the library ships only with the plugin. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes to check and reports a PASS/FAIL/INFO table with Bash, node, jq, git, the .gitattributes eol= policy, the eol_normalizer_enabled toggle and hook registration; flags a missing git as silent, so the probe is its only visibility; writes and edits nothing.'
---

/eol-normalizer:setup check
