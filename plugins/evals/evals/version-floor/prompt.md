---
description: "Hard case. Why hard: The message text invites a sign-up or a beta flag; the floor version and the meaning of each message are this plugin's preflight record."
tags: [preflight, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer names the 2.1.269 floor, says the early-access message comes from a binary below it so update Claude Code (no sign-up), and says 'currently unavailable' means the command is switched off on Anthropic's side for now, which can change at any time and may depend on account or context, and nothing local fixes"
---

Running `claude plugin eval ./plugins/notes` prints 'plugin eval is currently in early access', and `claude --version` says 2.1.240. Do I need to sign up somewhere to get access? My teammate, on a newer build, gets 'plugin eval is currently unavailable' instead. Is there a setting either of us can flip? Answer in under 150 words.
