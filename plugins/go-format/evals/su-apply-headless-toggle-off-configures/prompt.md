---
description: "apply asked how to turn the hook off headless. setup SKILL.md toggle bullet: reconfigure through the native configure flow, through the headless claude plugin configure route (configure-route accepts only that route, since the prompt rules out the interactive one), with the routes and caveats read from the plugin-local copy of the plugin-reconfiguration convention; never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-local copy of the plugin-reconfiguration contract the skill links, and fallback-after-configure, rerun-still-writes and scope-rule grade them there. configure-route also accepts a flag before the target. Legacy 'ends by rerunning check' is the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the headless change to the native configure flow for go-format@<marketplace> with go_format_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the fallback, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and go by the observed value; runs no claude plugin write itself."
---

/go-format:setup apply

I'm on a CI box with no interactive session. How do I turn the go-format hook off? What if this Claude Code release has no plugin configure, and does that rerun do anything when the plugin is already installed? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, what if the working directory is my home directory, and what goes wrong if I pass the wrong scope? How do I tell it worked?
