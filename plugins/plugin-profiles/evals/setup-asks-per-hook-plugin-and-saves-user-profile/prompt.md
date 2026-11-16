---
description: "AC25. The scaffold adds the local marketplace fixture-market to the run's temporary home and installs notes-hooks (ships a SessionStart hook, skill jot) and draw (skill sketch). The prompt answers the work interview and declines the recording offer but leaves the per-hook choice open, so one headless session shows setup running inventory and usage, then ending its turn on the question whether notes-hooks is always on or per profile, with no profile saved. per-hook-question-asked reads the final reply; no-profile-saved-before-answer fails any save run with --yes; no-hand-written-profile fails a profile file written with the Write tool. The slash prompt loads the skill without a Skill call, so no skill-fired grader; the CLI graders are with-only (the CLI ships only with the plugin) and match the script path however it is spelled. This case cannot run in the claude plugin eval sandbox today: the run's configuration directory is write-denied there, and the nested claude that inventory calls is not reachable. It is kept for when the harness allows nesting; the behavior is proven by a headless claude -p session instead. Needs --scaffold --allow-tools Bash Skill Write."
tags: [plugin-profiles, profile, setup, outcome]
runs: 1
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write]
expected_outcome: "Setup lists notes-hooks and draw with their skills, then asks whether notes-hooks is always on or per profile and stops there, saving nothing."
---

/plugin-profiles:profile setup

I write documentation and sometimes sketch diagrams; building docs is my only phase, with no exploring, planning, reviewing, interface design or harness upkeep. No session recording for now. I want one profile named docs at user level, described as "Write docs and sketch diagrams."
