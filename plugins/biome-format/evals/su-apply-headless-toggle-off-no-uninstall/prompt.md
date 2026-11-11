---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: set biome_format_enabled through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-convention); never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session. The routes' flags, version floor, fallback, scope rule and failure signals are graded nowhere, since the skill no longer states them; the prompt still asks about them, so the reply should route those questions to the convention. Legacy 'ends by rerunning check' is the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself, since the skill never writes user settings or pluginConfigs. The scaffold declines the entry so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [biome-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the change to the native configure flow for biome-format@<marketplace> with biome_format_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/biome-format:setup apply

I'm on a CI box with no interactive session. How do I turn the biome-format hook off? What if this Claude Code release has no plugin configure, and does the rerun do anything when the plugin is already installed? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, what goes wrong if I pass the wrong scope, where does the value end up, and how do I tell it worked?
