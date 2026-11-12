---
description: "check in a repository that never installed the pre-commit entry. setup SKILL.md check lines 65-68 (read the scripts, probe, report a PASS/FAIL/INFO table with one remediation line per FAIL), step 1 (line 73), step 2 (lines 74-76: PATH only, resolved path and typos --version), step 3 (lines 77-82: config INFO), step 4 (lines 83-86: unexpanded or empty spelling_end_of_turn means false, so findings wait for the commit), step 5 (lines 87-92: node --version, a command -v node hit is not enough) and step 6 (lines 93-99: missing is FAIL with apply install-git-hooks, declined is INFO). Changed legacy expectation: 'names the remediation in the same line' becomes a remediation named for the FAIL, because line 68 asks for one remediation line per FAIL, which may sit below the table. The command -v typos row is pre-computed at load (line 20), so only the version read is graded as a live call. The scaffold opts the clone in, so a global decline cannot change verify's missing. Host-bound: needs typos and node on PATH. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, check, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify, typos --version and node --version run; no install, spell-check run, install.mjs write verb, plugin CLI write, Write or Edit; the reply is a PASS/FAIL/INFO table covering Bash, typos, config, options, Node.js and the git entry; it says typos resolves from PATH only and gives its path and version, grades the missing entry FAIL with apply install-git-hooks, says a declined entry is INFO, and says an empty spelling_end_of_turn means false so findings wait for the commit."
---

/spelling:setup check

Where do you look for the typos binary, and does a per-repo install count? This clone never installed the pre-commit entry: how do you grade that, and what fixes it? How would you grade it if this clone had declined the entry instead? What is spelling_end_of_turn here, what does an empty or unexpanded value mean, and when do findings arrive then?
