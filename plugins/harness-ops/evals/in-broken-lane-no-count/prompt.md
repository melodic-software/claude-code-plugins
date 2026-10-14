---
description: "Answering from a saved inventory whose builtin_commands lane is degraded and bundled_skills lane is broken: the skill reports the 12 commands as a floor, withholds the bundled-skill count and names the broken lane. Reaches SKILL.md 'Staying current as Claude Code ships' (the per-lane integrity status table). Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, inventory, outcome, integrity]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply gives the built-in command count as a floor (at least 12, because that lane is degraded), gives no count for bundled skills, and says the bundled_skills lane is broken with its cause (canary simplify not resolved)."
---

/harness-ops:inventory --builtin --bundled

Answer from the inventory I saved an hour ago at ./claude-inventory.json; don't rerun the script. How many built-in commands and how many bundled skills does this build have?
