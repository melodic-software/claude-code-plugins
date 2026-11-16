---
description: "AC4, AC20. The scaffold adds fixture-market to the run's temporary home and installs notes-hooks only; draw stays uninstalled in a marketplace the machine knows. The user asks for a user-level profile art with draw and says yes to installing it after the preview. The skill previews install draw@fixture-market with --dry-run, then runs it once with --yes; the CLI prints 'Installed draw@fixture-market; it is off in <user settings>' (ends-off-at-user-level, trace). no-direct-install fails any claude plugin install, update, uninstall, enable or disable typed outside the CLI. This case cannot run in the claude plugin eval sandbox today: the run's configuration directory is write-denied there, and the nested claude that inventory and install call is not reachable. It is kept for when the harness allows nesting; the behavior is proven by headless claude -p sessions and, for install, by scripts/install-real-claude.test.mjs instead. Needs --scaffold --allow-tools Bash Skill."
tags: [plugin-profiles, profile, setup, install, outcome]
runs: 1
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, AskUserQuestion]
expected_outcome: "The install preview for draw is shown, the install runs once after the user's yes, and draw ends switched off in user settings."
---

/plugin-profiles:profile setup

Skip the interview: I only want a user-level profile named art, described as "Sketch diagrams.", holding draw@fixture-market, and no hook questions since notes-hooks stays as it is. Save art when you have shown it. draw is not installed yet: show me what installing it does first, and once you have shown that, my answer is yes, install it.
