---
description: "check in a repository with no markdownlint config. setup SKILL.md step 3 (lines 64-67: a missing jq is INFO without the opt-in, and the missing config, not jq, is why) and step 5 (lines 80-83 and 90-94: no rewrite, findings or notice; INFO, inactive, not PASS; the remediation in the same line; markdownlint's default rules are never the fallback). Narration: the eval host has jq and the load-time row shows it, so the prompt asks what a missing jq would grade. Legacy 'leads with the missing config' is dropped: line 210 says that for apply, and check reports a table. file_exists sees a config created by any tool. The clone declined the pre-commit entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Answers that the missing config, not jq, is why nothing happens: a missing jq is INFO here, the path is INFO, inactive, not PASS, with the remediation beside it; no rewrite, findings or notice; no default rules apply. No install, lint run, write or edit, and no config appears."
---

/markdown-format:setup check

There is no markdownlint config in this repo. Why is nothing getting formatted, and what would fix it? Would a missing jq be a FAIL in this state, and is jq or the config the reason nothing happens? How do you grade the hook for a path no config governs? Does the hook produce any rewrite, findings or notice in the meantime, and do markdownlint's own default rules apply until we add a config?
