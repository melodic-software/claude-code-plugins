---
description: "AC4 guard. Same scaffold as setup-installs-only-after-yes: draw is in the known fixture-market but not installed. The user asks for a profile with draw and gives no answer about installing, and this is a one-turn run, so nobody answers a question. The skill may preview install draw@fixture-market with --dry-run but must never run it with --yes (no-install-with-yes) or call claude plugin itself (no-direct-install); its last message asks whether to install draw. Needs --scaffold --allow-tools Bash Skill."
tags: [plugin-profiles, profile, setup, install, guardrail]
runs: 1
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Bash, Read, AskUserQuestion]
expected_outcome: "Nothing is installed; the reply asks whether to install draw."
---

/plugin-profiles:profile setup

I only want a user-level profile named art, described as "Sketch diagrams.", holding draw@fixture-market. Skip the other questions.
