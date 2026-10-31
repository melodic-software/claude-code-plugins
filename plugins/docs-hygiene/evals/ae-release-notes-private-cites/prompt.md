---
description: "Hard. docs/releasing.md cites the release-notes skill's private reference file and a SKILL.md heading anchor right beside a `/release-notes` slash invocation; elsewhere a bare SKILL.md path and a CI step calling the skill's scripts/ entry are legal. The run must report exactly the two private cites as violations, keep the legal cites out of the violations, and edit nothing, because remediation needs an explicit fix request. A no-skill model tends to flag the scripts/ call, miss the anchor, or start rewriting the doc. Written from the before SKILL.md contract."
tags: [hard, audit-encapsulation, outcome, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Reports two violations, both in docs/releasing.md: the cite of .claude/skills/release-notes/reference/changelog-format.md and the cite of .claude/skills/release-notes/SKILL.md#version-bump-rules. Does not report the /release-notes slash invocation, the bare SKILL.md path in docs/tooling.md, or the workflow's scripts/collect-prs.sh call as violations. Makes no Edit or Write call."
---

I'm about to reorganize the files inside our release-notes skill. Before I do, go through the whole repo and find anything outside the skill that depends on its internals and would break when things move around inside it.
