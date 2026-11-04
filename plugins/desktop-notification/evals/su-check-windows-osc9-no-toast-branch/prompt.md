---
description: "check, then a question about a teammate on Windows. setup SKILL.md lines 87-89: INFO, no os_toast branch because a fire-and-forget process leaves no live activator host for a WinRT toast, terminal_notify OSC 9 carries attention, nothing to install. Narration: the host need not be Windows, so the prompt asks about a teammate, and the graders read the Windows answer only: a Linux host's own notify-send guidance still passes. Legacy 'does not prescribe notify-send or libnotify' and 'does not offer to install or repair' are merged into nothing-to-install-on-windows. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "For the Windows teammate: INFO, not FAIL; no toast branch, with the activator-host reason; terminal_notify (OSC 9) carries attention; nothing to install. No install, Write or Edit."
---

/desktop-notification:setup check

Run the check on this machine first. Then a question about a teammate on Windows who never gets a desktop toast: how does check grade the OS toast row on Windows, why does the hook have no toast there, which channel carries attention instead, and what do they need to install?
