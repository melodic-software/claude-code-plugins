---
description: "Status reading: the user says status reported OptiScaler.ini changed and asks whether the install is broken. The reply must say a changed OptiScaler.ini is expected (the overlay's Save Settings rewrites it) and does not make status exit 1, and say what exit 1 would mean: a pre-install file modified or removed, or a manifest file other than OptiScaler.ini missing or changed (dlss5/SKILL.md lines 294-315). Status runs at most once. The status run itself happened on the user's gaming PC, so the case grades the explanation. Needs --allow-tools Bash so the at-most-once grader can fail."
tags: [gaming, dlss5, outcome, status, drift]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply says OptiScaler.ini drift is expected after Save Settings and keeps status at exit 0, so the install is not broken, and says exit 1 would mean a pre-install file was modified or removed or a manifest file other than OptiScaler.ini is missing or changed. No more than one Bash command runs the status verb."
---

/gaming:dlss5 status G:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64 - it says OptiScaler.ini changed, is my install broken?

This session is not on my gaming PC; the status run was over there.
