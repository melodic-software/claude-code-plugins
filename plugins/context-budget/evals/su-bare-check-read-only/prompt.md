---
description: 'setup with no argument runs the read-only check. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md line 37: no argument runs check, non-interactive, never prompts; lines 41-46: read the audit skill''s Prerequisites and the measure.mjs header first, then report a PASS/FAIL/INFO table, modify and install nothing. status-table-all-rows grades the table (a leading row-number column allowed); reads-audit-prereqs and reads-engine-header (with-only indicators, Read or a shell reader in the trace; reads-audit-prereqs also takes a content-mode Grep, which prints the section''s lines) grade the sources read; no-ask-tool, no-install, no-plugin-command-run, no-edit and no-write grade the read-only posture. One remediation line per FAIL is not graded: it applies only when the host yields a FAIL. Bash is granted for the pre-computed probe lines. Needs --allow-tools Bash; may need --disallow-tools Grep if a run greps the plugin dir.'
tags: [context-budget, setup, outcome, check-only, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'With no argument the run performs check without asking: it reads the audit SKILL.md and the measure.mjs header, reports a PASS/FAIL/INFO table with rows for node, the Claude Code CLI, the Agent SDK and the settings-write-ask toggle, and installs, configures, edits and writes nothing.'
---

/context-budget:setup
