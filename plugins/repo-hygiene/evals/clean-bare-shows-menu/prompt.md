---
description: "Bare invocation with no signal shows the menu and asks. Slash-invoked, so there is no Skill grader. clean SKILL.md lines 112-114: infer from conversation; if still unclear, present the action table and ask; safest fallback scan. action-router.md lines 56-60: no match presents the table and asks, and scan is the default when still unsure. The scaffold's working tree is clean and the prompt carries nothing else, so no action can be inferred. shows-action-table needs the scan, caches, build, stash and tree rows; asks-choice needs the question; names-scan-fallback needs scan called the safest or default fallback. no-tier-run fails any tier script, dry-runs and the read-only scan included, since running one is guessing; resolve-clean-action.sh and the gather calls stay allowed. Bash is granted so no-tier-run and no-apply can fail. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, menu, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply lists the actions (scan, caches, build, git, stash, tree, all and the batch forms), asks which one to run, and names scan as the safe fallback; no tier script runs."
---

/repo-hygiene:clean
