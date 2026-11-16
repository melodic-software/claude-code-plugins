---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Starts a named receiver on the desktop''s own Windows lane (R1) in its build plugin profile through one PowerShell script sent on stdin to powershell.exe -Command -: the script finds profiles.mjs through claude.exe plugin list --json, runs profiles.mjs launch build --unattended --json with the receiver''s settings in --with, removes each variable argv names after -u with Remove-Item Env:, and starts claude.exe with the rest of argv. No env -u line runs before claude.exe. Says that with plugin-profiles missing the session starts without the profile and the reply says so, and that a refused launch starts nothing.'
---

I'm in the desktop's WSL session (desk-01). Start a Claude session on this machine's Windows side, in its `build` plugin profile, that other sessions can keep sending messages to. Give me the exact commands to run; don't run them yourself, and run no shell command to work them out.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
