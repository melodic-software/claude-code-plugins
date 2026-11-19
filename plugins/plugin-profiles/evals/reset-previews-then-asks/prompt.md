---
description: "AC10 reset action: the scaffold makes the run's work folder a git folder whose settings.local.json holds one entry profile build wrote, with its record under .git/plugin-profiles and the pointer reset finds it by under the run's own config folder. The user asks in plain words to undo every profile on the machine and gives no yes. The skill fires, runs profiles.mjs reset --dry-run, and stops at a question: reset-previewed is with-only; no-write fails any apply, clear, reset, save or install run with --yes; asks-first reads the last message. Needs --scaffold --allow-tools Bash Skill."
tags: [plugin-profiles, profile, reset, outcome, no-network]
runs: 1
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read]
expected_outcome: "The reset preview runs and is shown, and the reply asks whether to go ahead, writing nothing."
---

I've been trying plugin profiles in a few repos and want to undo all of it. Put every folder on this machine back the way it was before any profile.
