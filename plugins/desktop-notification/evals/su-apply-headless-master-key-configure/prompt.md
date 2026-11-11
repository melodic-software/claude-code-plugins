---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: set the toggle's key through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-convention); one channel is muted through its own key (check step 5 names them); never uninstall to reconfigure; a same-session check can still show the old value, so rerun check in a fresh session and report the observed value. The routes' flags, version floor, fallback, scope rule and failure signals are graded nowhere, since the skill no longer states them; the prompt still asks about them, so the reply should route those questions to the convention. Legacy 'ends by rerunning check' is now the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes to the native configure flow for desktop-notification@<marketplace> with desktop_notification_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; one channel through its own key; rules out uninstalling; rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/desktop-notification:setup apply

I'm on a CI box with no interactive session. How do I turn the notification hook off? What if this Claude Code release has no plugin configure, and does the rerun do anything when the plugin is already installed? How would I mute just one channel instead? Could I just uninstall and reinstall? Which scope do I use and where do I run it, and how do I tell it worked?
