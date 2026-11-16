---
description: "AC15, AC25. The scaffold adds the local marketplace fixture-market to the run's temporary home and installs notes-hooks (ships a SessionStart hook, skill jot) and draw (skill sketch). Setup should run the CLI's inventory and usage commands, settle per-profile for notes-hooks, preview the save of profile docs with --dry-run, then save it with --level user --yes on the stated yes. The slash prompt loads the skill without a Skill call, so no skill-fired grader; the CLI graders are with-only (the CLI ships only with the plugin) and match the script path however it is spelled; no-hand-written-profile fails a profile file written with the Write tool. This case cannot run in the claude plugin eval sandbox today: the run's configuration directory is write-denied there, and the nested claude that inventory and install call is not reachable. It is kept for when the harness allows nesting; the behavior is proven by headless claude -p sessions and, for install, by scripts/install-real-claude.test.mjs instead. Needs --scaffold --allow-tools Bash Skill Write."
tags: [plugin-profiles, profile, setup, outcome]
runs: 1
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, AskUserQuestion]
expected_outcome: "Setup lists notes-hooks and draw with their skills, records notes-hooks as per profile, previews profile docs, then saves it at user level through the CLI."
---

/plugin-profiles:profile setup

I write documentation and sometimes sketch diagrams. My answers up front, so you need not ask: notes-hooks is per profile, not always on. Make one profile named docs at user level holding notes-hooks and draw, described as "Write docs and sketch diagrams." Yes, save it once you have shown me the file.
