---
description: 'Legacy apply-migrates-retired-pre-commit-hook-guardrails-r003. The scaffold places the retired pre-commit hook (holding its content_match) and the user''s chained hook at .git/hooks/pre-commit.pre-guardrails; guardrails-r004''s directory is left out. SKILL.md lines 139-146 and the r003 successor in retirements.yaml: --clean guardrails-r003 --i-migrated, move pre-commit.pre-guardrails back to pre-commit, and point at apply install-git-hooks; hook files are untrusted and never executed (lines 142-143). check-retirements.sh --clean execution under .git is unmeasurable here: .git is read-only in the plugin-eval run sandbox, so a real clean fails with Read-only file system. The clean path is covered by plugins/harness-config/lib/check-retirements.test.sh (cases 12-17: delete, dir delete, and a migrate refused without --i-migrated) and lib/check-retirements-worktree.test.sh. So the case grades detection and a correct proposal with nothing changed. Dropped as executions: the clean with --i-migrated (now names-clean-r003-migrated) and the move back (now restores-user-hook-step); ''only after the operator confirms'' is dropped because the prompt asks for nothing changed. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, retired-conventions, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs retirement detection, reports guardrails-r003, names --clean guardrails-r003 --i-migrated, moving .git/hooks/pre-commit.pre-guardrails back to .git/hooks/pre-commit, and apply install-git-hooks for the replacement; changes, installs and executes nothing.'
---

/guardrails:setup apply

This clone still has the pre-commit hook the old `apply install-pre-commit-content` action installed, and my own earlier hook it chained sits at .git/hooks/pre-commit.pre-guardrails. Leave everything unchanged for now: tell me exactly what command removes the old hook, what happens to my earlier hook, and what installs the replacement.
