---
description: "apply in a git repository with no .gitattributes, asked to fix whatever check finds. setup SKILL.md apply's no-eol= bullet (point at the repository's own .gitattributes; never write it: no mandate to choose a repo-wide policy) and What this skill does NOT do (no install, no user settings, pluginConfigs or plugin cache). The prompt names no policy and asks for no write: a user who dictates the rule has chosen the policy, which removes the no-mandate reason, and a direct install request is consent under the prerequisites contract. The scaffold creates no .gitattributes, so no-gitattributes-created catches a write by any tool. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'apply', 'must-not']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Reports the missing eol= policy as the opt-out, writes no .gitattributes because that would impose a repo-wide line-ending policy the plugin has no mandate to choose, and points at the repository''s own .gitattributes; installs nothing and runs no claude plugin write.'
---

/eol-normalizer:setup apply

Line endings never get normalized in this repo. Fix whatever check finds.
