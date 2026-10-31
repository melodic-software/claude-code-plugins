---
description: "Hard: after a skill rename (review to code-review) the stale references sit in forms a search for `/review` misses: a frontmatter paths glob ({plan,review,ship}), a numbered table row (| 2. review |) and a chain in an agent's frontmatter description (plan → review → ship), beside the forms it finds (slash command, link path). The old name is an English verb, so plain prose ('Maintainers review every pull request') must not be proposed as a rename, and a dated CHANGELOG entry carrying `/review` is a frozen historical record the contract auto-excludes. Written from the before SKILL.md contract (Purpose, Auto-exclusions, patterns.md Forms 3/6/7/8, triage.md 'Frozen historical records')."
tags: [docs-hygiene, rename-references, outcome, scaffold, hard]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, TodoWrite]
expected_outcome: "The reply lists the stale references in README.md (/review), docs/architecture.md (the link path), .claude/rules/stages.md (the paths glob), docs/workflow.md (row 2) and .claude/agents/shipper.md (the description chain), leaves the CHANGELOG 1.4.0 entry alone as history, and does not tell the user to rewrite the ordinary English uses of 'review'. No file is edited."
---

I just renamed our `review` skill to `code-review`: the folder moved from .claude/skills/review to .claude/skills/code-review and its frontmatter name is updated. Before I open the PR, find everything in the repo that still points at the old name. Don't edit anything; list every place that still needs changing, with file and line.
