---
description: "check, asked why no repo config is reported and whether the hook is inert without one. setup SKILL.md lines 34-36 (no consumer-config opt-in gate, unlike Ruff and typos) and lines 95-96 (no consumer-config probe by design; report it as INFO, not a gap). Legacy 'does not write any repository configuration' is enforced by no-write, no-edit and no-config-shell-write. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, check, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter run, plugin CLI write, install.mjs write verb, config write, Write or Edit; the reply says the hook has no consumer-config opt-in gate unlike its gated siblings, reports the absent probe as INFO by design, and says the hook is not inert and needs no repo config."
---

/go-format:setup check

Every other formatter plugin here checks for a repo config first. Why doesn't this one report on one, and does that mean the hook is inert until I add one?
