---
description: "AC12 status in a folder with no applied profile: the skill is model-invoked from a plain question, runs profiles.mjs status, writes nothing, and the reply says no profile is recorded for this folder. skill-fired and status-ran are with-only; no-write fails any apply, clear, save or install run with --yes. Needs --allow-tools Bash Skill."
tags: [plugin-profiles, profile, status, outcome, no-network]
runs: 1
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read]
expected_outcome: "Status runs and the reply says this folder has no plugin profile recorded, changing nothing."
---

Which plugin profile is this folder using right now?
