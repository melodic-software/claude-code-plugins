---
description: "Hand-off step of unattended after the user approved the STAGES block of an existing script: the agent's only run is pwsh -File <script> -Test (expected to stop at the elevation check), and it tells the human to run -WhatIf first, then the real launch elevated through pwsh -File on PowerShell 7, without asking for the transcript. The case most likely to fail for the wrong reason: a faithful skill may print the STAGES block and ask again. Needs --scaffold --allow-tools Bash."
tags: [wizard, unattended, outcome, hand-off, never-launch]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The agent runs pwsh -File retire-distro.ps1 -Test, reads result-dry-latest.json, runs it with no switch other than -Test (no -WhatIf, no real run), and tells the user to run -WhatIf first and then launch it with pwsh -File from an elevated PowerShell 7 session, without asking them to paste the output back."
---

/wizard:unattended retire-distro.ps1 in this folder is the script you drafted to back up and remove my Debian-build distro. I've read the STAGES block and I'm fine with it as written. Take it from here.
