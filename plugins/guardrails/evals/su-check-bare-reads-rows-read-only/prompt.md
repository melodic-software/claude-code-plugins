---
description: 'Legacy check-is-default-and-read-only. Bare /guardrails:setup routes to check (SKILL.md lines 40-44) in a fresh git repo. jq and node are pre-computed at load (lines 18-27), so no-jq-node-reprobe is arm with-only: the without arm has no pre-computed block. status-table reads the Bash, jq and node rows (lines 60-69); bash-probe the bash the hooks run (lines 60-63); advisory-guards-off the manifest defaults (lines 70-74); allowlist-empty the block_dangerous_git_allow row (lines 83-84); verify-ran step 5 (lines 75-82); retirements-ran step 8 (lines 87-93). Legacy ''reports a missing node as FAIL with the README Requirements remediation'' is narration (the host has node), so the prompt asks it as a hypothetical. Dropped: ''routes to check when no argument is given'' (the table and the read-only graders show it), ''rather than inventing configuration'' (not judgeable), and expected_output''s cli-flag-verify scan surface, which check no longer has. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, check, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'A PASS/FAIL/INFO table with Bash, jq and node rows, the hooks'' bash probed, workflow-resilience-check and flag-commit-pr-skill-bypass off by default, an empty dangerous-git allowlist, verify and retirement detection run; node missing would be FAIL with a Node.js install fix; jq and node not re-probed; no install, plugin CLI write, settings write, Write or Edit.'
---

/guardrails:setup

For each row, give the evidence it rests on. Include the version of the bash the hooks run, every guard's on/off value, and the dangerous-git allowlist. Then: on a teammate's machine with no node at all, what would the node row say and what is its fix?
