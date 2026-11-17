---
description: "check, then asked how the concerns and missing prerequisites are graded. setup SKILL.md check (read the scripts, probe, report a PASS/FAIL/INFO table), step 2 (node FAIL), step 3 (jq FAIL), step 4 (the format and lint concerns each resolve on their own through the entries' --resolve rows; a concern with no adapter config is INFO unresolved), step 6 (effective option values), step 7 (registration through /plugin, not settings files) and step 10 (install.mjs verify, the live sign check ran, since the pre-computed block tells the run to read the command -v rows instead of re-issuing them). Changed expectations: a missing .shellcheckrc is INFO because the lint concern is then unresolved and no ShellCheck runs, no longer because ShellCheck applies its defaults; the table no longer needs separate config-file rows, since the shfmt and ShellCheck concern rows carry them. Narration: the eval host has node and jq, so the prompt supposes the absences. The scaffold opts in to both concerns and declines both entries, so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter or linter run, install.mjs write verb, settings-file read, Write or Edit; the reply is a PASS/FAIL/INFO table with separate shellcheck and shfmt rows, says missing node and jq are FAIL with their consequences, a missing .shellcheckrc is INFO, reports the three effective option values and confirms registration through /plugin."
---

/bash-format:setup check

Are the lint concern and the format concern one verdict or two? Suppose node or jq were missing here: how would you grade each, and what would stop working? Would a missing .shellcheckrc be a FAIL? What are the hook option values in effect, and how do you confirm the hook is registered?
