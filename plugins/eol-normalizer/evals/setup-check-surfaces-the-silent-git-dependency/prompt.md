---
description: "Explicit check in a git repository with an eol=lf rule, plus a question about a machine without git. setup SKILL.md: check reads the entry script and the sourced normalize-eol.sh library, reports a PASS/FAIL/INFO table, and step 4 says a missing git emits no notice so the probe is the only visibility; it confirms registration through /plugin Installed and modifies nothing. Step 4 gives the silence only for an absent git, and the run's host has git, so the prompt asks about that case directly. status-table needs jq, git and node rows; node is a current check row the legacy expectation predates. read-sourced-library is a with-only indicator: the library ships only with the plugin. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes to check and reports a PASS/FAIL/INFO table with Bash, node, jq, git, the .gitattributes eol= policy, the eol_normalizer_enabled toggle and hook registration; says a missing git would emit no notice, so this probe is its only visibility; writes and edits nothing.'
---

/eol-normalizer:setup check

If git were missing on one of our other machines, how would I find out?
