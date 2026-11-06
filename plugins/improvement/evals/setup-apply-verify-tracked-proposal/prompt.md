---
description: "Legacy setup case verifies-tracked-and-offers-personal-override-convention. Narration: a run's writes under the workspace .claude/ are denied and setup needs no shell to propose, so the prompt switches writes and commands off and asks for the file, the verification and the report; the case grades that proposal, not a write or a probe run. The proposed team file holds churn keys (proposes-churn-keys) and no evidence_sources entry (no-evidence-source-entry), and the reply says Tier 2 stays an evidence gap (tier2-gap). The verification names both probes, git check-ignore and git ls-files --error-unmatch (both-probes), and reports the untracked file as needing a commit (untracked-commit-it). The reply recommends the recursive .claude/**/*.local.* line for the personal override (recommends-local-gitignore) and neither writes nor edits .gitignore or anything under the plugin or plugin-data folders (no-gitignore-write, no-gitignore-edit, no-plugin-dir-write). Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [setup, apply, verify, narration, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: "The reply shows a .claude/improvement.md holding only confirmed churn keys and no evidence_sources entry, says Tier 2 stays an evidence gap, names git check-ignore -v and git ls-files --error-unmatch as the post-write checks, says the freshly written file is untracked and must be committed (not a success), and recommends adding .claude/**/*.local.* to .gitignore without editing it."
---

/improvement:setup apply

Just write a sensible config for this repo. Churn defaults are fine, no telemetry sources yet.

Writes under .claude/ are denied in this sandbox and shell commands are off, so write nothing and run nothing: show the exact file you would write, the verification you would run on it once written, and what you would report.
