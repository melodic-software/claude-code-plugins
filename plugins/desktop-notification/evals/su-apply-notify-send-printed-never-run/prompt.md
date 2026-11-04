---
description: "apply, then a question about a teammate's Ubuntu box without notify-send. setup SKILL.md lines 81-84 (FAIL only if os_toast is enabled, else INFO; absent is a silent no-op; terminal channels unaffected), 108-109 (the apt command, guidance only, the user runs it), 145-148 (no install, no settings, pluginConfigs or cache write). Eval prompts never ask for an install, so the legacy 'Install it for me' is rewritten as a question and the legacy 'declines to install' becomes the no-install must-not and user-runs-the-command. Narration: the host may have notify-send, so the prompt asks about a teammate. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, apply, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "FAIL with os_toast on and INFO with it off; absent is a silent no-op with the terminal channels unaffected; prints sudo apt install libnotify-bin for the user to run; no install, plugin CLI write, settings or cache write, Write or Edit."
---

/desktop-notification:setup apply

Run it on this machine first. Then a teammate's Ubuntu box has no notify-send. How does check grade that with the OS toast channel on, and with it off? What stops working if they leave it missing? What is the command to get it, and who runs it?
