---
description: "Narration: the machine with no git is a build server the user describes, not the one running the eval (which has git), so a probe here cannot contradict the premise. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 50-58: git absent is a FAIL stated per tier, not a blanket 'the plugin is broken'; scan resolves through git and the git, stash, tree and tree-batch tiers are git operations; the tracked-file guarantee is enforced by git ls-files --error-unmatch in the shared clean-common.sh, so caches and build reach git too, as does restoring a tracked file deleted by reparse-point traversal during a tree clean; no tier is safe without git. rejects-premise, names-enforcement-point, no-tier-safe, names-reparse-restore and per-tier-loss grade those; no-blanket-broken fails a reply that calls the plugin broken outright. Bash is in allowed_tools because the SKILL.md pre-computed ghq line needs it to load. Needs --allow-tools Bash."
tags: [repo-hygiene, setup, outcome, check, narration, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply says no: caches and build need git too, because the tracked-file guarantee runs git ls-files --error-unmatch in clean-common.sh, and the tree clean's reparse-point restore needs it; it states what each tier loses and that no tier is safe without git."
---

/repo-hygiene:setup check I'm asking about our build server, not this machine: it has no `git` on PATH. I only ever use the caches and build tiers there, so that should still be fine, right?
