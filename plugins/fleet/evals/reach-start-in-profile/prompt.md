---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Starts a named receiver on the laptop''s WSL install in its build plugin profile: finds profiles.mjs on the laptop through claude plugin list --json (the installPath of the enabled plugin-profiles@ entry), runs profiles.mjs launch build --folder <dir> --unattended --json there with the receiver''s crossSessionInbound settings passed through --with, and starts the receiver with the printed command in place of claude. Says that a launch refused for a missing required tool starts nothing and is reported.'
---

I'm in the desktop's WSL session (desk-01). Start a Claude session on the laptop's WSL side, in its `build` plugin profile and in `~/repos/app`, that other sessions can keep sending messages to. Give me the exact commands to run; don't run them yourself, and run no shell command to work them out.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
