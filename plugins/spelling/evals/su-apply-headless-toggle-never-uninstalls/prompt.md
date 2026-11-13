---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: set spelling_enabled to false through the native configure flow, through the headless claude plugin configure route (configure-route accepts only that route, since the prompt rules out the interactive one), with the routes and caveats read from the plugin-local copy of the plugin-reconfiguration convention; never uninstall to reconfigure; a same-session check can still report the old value, so rerun check in a fresh session and report the observed value. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-local copy of the plugin-reconfiguration contract the skill links, and configure-minimum-release, fallback-after-configure, rerun-still-writes, repeatable-per-key and scope-rule grade them there. The skill never writes user settings or pluginConfigs, so no-plugin-cli-write guards a claude plugin write the run makes itself. The scaffold declines the entry so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the headless change to the native configure flow for spelling@<marketplace> with spelling_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/spelling:setup apply

I'm on a CI box with no interactive session. How do I turn the spelling hook off? Which Claude Code release do I need for that, what if mine is older, and does the older route do anything when the plugin is already installed? Can that route set spelling_end_of_turn in the same command? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, what goes wrong if I pass the wrong scope, where does the value end up, and how do I tell it worked?
