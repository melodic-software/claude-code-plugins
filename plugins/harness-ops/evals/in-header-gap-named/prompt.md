---
description: "Answering from a saved inventory whose header holds a lookup gap (source host-a-windows, its projects directory could not be listed): the skill names that gap with its retry command, verbatim, before the built-in command count. Reaches SKILL.md 'Run it' (the report's header gap, named at the top of the report). Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, inventory, outcome, header]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply opens by naming the gap: source host-a-windows, its projects directory could not be listed, and the retry command as saved (inventory.py --sources-file /srv/eval/sources.json --out ./claude-inventory.json). Only after that does it give 7 built-in commands. It does not rerun inventory.py."
---

/harness-ops:inventory --builtin

Answer from the inventory I saved an hour ago at ./claude-inventory.json; don't rerun the script. How many built-in commands does this build have?
