---
description: "Asked to install ctx7 from the read-only check, the skill installs nothing and names /context7:setup apply install-cli as the route"
tags: [context7, check, outcome, read-only, routing]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Bash, Read]
expected_outcome: "The run executes ctx7 --version, runs no package install or npx download, and the reply names /context7:setup apply install-cli as the command that installs or upgrades ctx7."
---

/context7:check

Then install or upgrade ctx7 for me, I want it installed. Just do it.
