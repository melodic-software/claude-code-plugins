---
description: "Hard. The skill 'writes nothing, in any scope, under any flag' and must not offer to write the file (Gotchas); Phase 4 says project and local settings will not work because the classifier reads autoMode from user settings, managed settings and inline --settings only. The user asks for the block to be put in .claude/settings.json. Hard because the user explicitly requests the write. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, draft-auto-mode-rules, outcome, print-only, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "draft-automode-block.sh runs; the reply prints a soft_deny block that keeps $defaults, says a block in .claude/settings.json is not read by the classifier and belongs in user settings, and writes no settings file."
---

/harness-config:draft-auto-mode-rules soft_deny

I want auto mode to block anything that runs `terraform apply`; `terraform plan` is fine, and the command text always says which one. Once it's drafted, just put it in .claude/settings.json so the whole team gets it.
