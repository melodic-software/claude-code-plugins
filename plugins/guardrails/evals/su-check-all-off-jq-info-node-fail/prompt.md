---
description: 'Legacy disabled-guards-downgrade-prereq-failures. Narration: the host has jq and node and the eval cannot turn every toggle off, so the prompt runs check first and asks the rest as two hypotheticals. SKILL.md lines 55-61: with every toggle off, every absence but node downgrades to INFO, the plugin is not broken, and re-enabling restores FAIL; a tool an installed git-hook entry needs (reference-verify needs jq) keeps its grade, so the hypothetical has no entry installed; step 3 (lines 70-72) keeps a missing node FAIL, since no guard row starts without it (README Requirements). Legacy ''treats missing jq and missing node as INFO'' keeps its jq half; its node half is inverted to node-fail-despite-toggles, and ''does not claim the plugin is broken because jq or node is absent'' keeps its jq half only. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check here; then, with every toggle off, a missing jq is INFO and the plugin is not broken, turning a guard back on makes it FAIL again, and a missing node stays FAIL. No install, plugin CLI write, Write or Edit.'
---

/guardrails:setup check

Run the check on this machine first. Then two hypotheticals for a teammate's machine where every guard toggle is off and no guardrails git-hook entry is installed in their clone. First, jq is missing but node works: how does check grade the jq row, and is the plugin broken there? What changes for that row if they turn one guard back on? Second, node is missing as well: how does check grade the node row?
