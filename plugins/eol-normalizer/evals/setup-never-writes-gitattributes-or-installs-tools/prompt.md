---
description: "apply asked to add an LF rule in a git repository with no .gitattributes. setup SKILL.md apply's no-eol= bullet (never writes .gitattributes: no mandate to choose a repo-wide policy) and What this skill does NOT do (no install, no user settings, pluginConfigs or plugin cache). The prompt asks for no install: a direct install request is consent under the prerequisites contract, so no-install guards an install the run chooses on its own. The scaffold creates no .gitattributes, so no-gitattributes-created catches a write by any tool. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'apply', 'must-not']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Declines to write .gitattributes, because that would impose a repo-wide line-ending policy the plugin has no mandate to choose, and points at the repository''s own .gitattributes; installs nothing and runs no claude plugin write.'
---

/eol-normalizer:setup apply

We want LF everywhere. Add the eol rule.
