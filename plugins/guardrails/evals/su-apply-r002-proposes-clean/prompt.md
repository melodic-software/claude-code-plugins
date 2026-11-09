---
description: 'Legacy apply-cleans-retired-resolver-guardrails-r002. SKILL.md lines 139-146: re-run detection, then for a delete record confirm and run check-retirements.sh --clean <id>, report what was removed, re-run detection last. check-retirements.sh --clean execution under .git is unmeasurable here: .git is read-only in the plugin-eval run sandbox, so a real clean fails with Read-only file system. The clean path is covered by plugins/harness-config/lib/check-retirements.test.sh (cases 12-17: delete, dir delete, and a migrate refused without --i-migrated) and lib/check-retirements-worktree.test.sh. So the case grades the branch a run can take: detection and a correct proposal with nothing changed. Dropped: ''runs check-retirements.sh --clean guardrails-r002'' as an execution (now names-clean-r002, a proposal) and ''cleanup runs only after the operator confirms'' (the prompt asks for nothing changed). ''Detection is re-run last'' is detection-after-clean, a proposal. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, retired-conventions, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs retirement detection, reports guardrails-r002, names check-retirements.sh --clean guardrails-r002 as the cleanup and a detection re-run after it; cleans, deletes, writes and edits nothing.'
---

/guardrails:setup apply

Only .git/hooks/guardrails-resolve-convention.sh is left from the old install-commit-msg action. Leave everything unchanged for now: tell me exactly what command removes this leftover and what you would do after it.
