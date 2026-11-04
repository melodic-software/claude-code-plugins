---
description: "check, then asked how the passes and missing prerequisites are graded. setup SKILL.md lines 54-59 (read the scripts, probe, report a PASS/FAIL/INFO table; the format and lint passes are independent, report each separately), step 2 (lines 67-69: node FAIL), step 3 (lines 70-71: jq FAIL), step 7 (lines 91-93: .shellcheckrc INFO), step 8 (lines 94-101: effective option values), step 9 (lines 102-103: registration through /plugin, not settings files) and step 12 (lines 121-127: install.mjs verify, the live sign check ran, since lines 20-21 tell the run to read the pre-computed command -v rows instead of re-issuing them). Changed legacy expectations: the node consequence said no shell edit is linted or formatted; it is now formatted only, since findings moved to the pre-commit entry (line 69, README lines 6-7). The jq consequence said silently; that word is dropped, because prerequisites.json declares jq and README lines 116-118 say the SessionStart probe reports it, and the pre-commit half of line 71 is added. The third option, bash_format_end_of_turn, is added to the reported values (line 99). Narration: the eval host has node and jq, so the prompt supposes the absences. The scaffold opts in, carries a .shellcheckrc and declines the entry, so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter or linter run, install.mjs write verb, settings-file read, Write or Edit; the reply is a PASS/FAIL/INFO table with separate shellcheck and shfmt rows, says missing node and jq are FAIL with their consequences, a missing .shellcheckrc is INFO, reports the three effective option values and confirms registration through /plugin."
---

/bash-format:setup check

Are the lint pass and the format pass one verdict or two? Suppose node or jq were missing here: how would you grade each, and what would stop working? Would a missing .shellcheckrc be a FAIL? What are the hook option values in effect, and how do you confirm the hook is registered?
