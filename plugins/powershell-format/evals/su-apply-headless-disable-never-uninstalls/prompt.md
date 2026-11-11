---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: reconfigure through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-convention); never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session. Step 6 (lines 81-83): any value other than true disables the hooks. The routes' flags, fallback, scope and failure signals are graded nowhere, since the skill no longer states them; the prompt still asks about them so the reply has to route those questions to the convention. Legacy 'ends by rerunning check' is now the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the change to the native configure flow for powershell-format@<marketplace> with powershell_format_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the fallback, the scope and the failure signals; rules out uninstalling; says any value other than true disables the hooks; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/powershell-format:setup apply

I'm on a CI box with no interactive session. How do I turn the powershell-format hook off? What if this Claude Code release has no plugin configure, and does the rerun do anything when the plugin is already installed? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, which values count as off, and how do I tell it worked?
