---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet (lines 110-135): claude plugin configure --values-stdin with every value a string is preferred; the claude plugin install --config rerun is the fallback before 2.1.285 and against an installed plugin prints already installed and still writes (lines 119-120); keys are repeatable per key (lines 116-119); never uninstall (lines 120-122); configure has no scope flag and runs from the project the plugin is installed in, -s defaults to user, so pass the scope claude plugin list reports (lines 123-126); a same-session check reports the old value, so rerun check in a fresh session and report the observed value (lines 131-135). The prompt raises each claim. Legacy 'cites the plugin-reconfiguration convention' and its record is dropped: the skill cites it as its own source and never tells the reply to name it. Legacy 'resetting all four toggles' now reads 'every option' (lines 121-122). Legacy 'ends by rerunning check' is now the fresh-session rerun. no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes to claude plugin configure desktop-notification@<marketplace> --values-stdin with {\"desktop_notification_enabled\": \"false\"}, then the claude plugin install --config rerun that still writes on an installed plugin; one channel through its own key; rules out uninstalling; gives the scope rule; rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/desktop-notification:setup apply

I'm on a CI box with no interactive session. How do I turn the notification hook off? What if this Claude Code release has no plugin configure, and does the rerun do anything when the plugin is already installed? How would I mute just one channel instead? Could I just uninstall and reinstall? Which scope do I use and where do I run it, and how do I tell it worked?
