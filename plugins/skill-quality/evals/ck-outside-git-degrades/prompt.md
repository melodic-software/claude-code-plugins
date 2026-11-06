---
description: "Legacy check eval 6. Asked what happens when the check runs outside any git repository against a plugin-cache skills root set through CHECK_SKILL_SKILLS_ROOT, the reply says the non-git checks still run and the git-backed checks skip with a note; the checker does not exit 2 for the working directory alone. check SKILL.md Gotchas, 'A git repository is optional' and the plugin-cache paragraph under Skills-directory resolution. names-git-backed-checks grades a git-backed check named by the hub (trigger-keyword preservation, vendor byte-identity, stale-tracking metadata, committed-artifact scan); skips-not-aborts grades the skip wording; degrades-not-aborts judges the whole answer; skill-fired is an indicator."
tags: [skill-quality, check, outcome, narration, read-only, no-network]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says the static gate still runs its non-git checks against the cache tree because CHECK_SKILL_SKILLS_ROOT gives it a skills root, the git-backed checks (trigger-keyword preservation, vendor byte-identity, stale metadata, committed-artifact scan) skip with a note, and the script exits 2 only when no skills root override, no CLAUDE_PROJECT_DIR and no git toplevel is available."
---

Run the skill-quality check from a working directory that is not inside any git repository, pointed at a marketplace plugin-cache skills root via CHECK_SKILL_SKILLS_ROOT. What happens?
