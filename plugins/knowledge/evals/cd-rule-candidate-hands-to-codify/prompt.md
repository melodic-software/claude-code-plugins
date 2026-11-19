---
description: "Phase 5 on an already digested fixture course with a corrections stand-in loaded. The invented course robust-http-apis-hale (scaffolded at courses/teachable/robust-http-apis-hale/, phase markers set through analyze, both module summaries and analysis/course-summary.md present) teaches one rule, validate request bodies at the boundary, and the scaffolded orders-api passes req.body to its store unvalidated. analysis/action-items.md must list that rule under Rule candidates as a /corrections:codify hand-off, not as a line to add to CLAUDE.md, AGENTS.md or a .claude/rules/ file, and the digest names the call without running it. No browser, download or extraction script. Visibility: the scaffold runs git init with no remote, so the work root reads local"
tags: [knowledge, course-digest, outcome, scaffold, rule-candidate, codify-handoff]
plugins: ["../..", "corrections-stub"]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run writes analysis/repo-candidates.md and analysis/action-items.md in the course directory. action-items.md has a Rule candidates section whose entry for validating request bodies at the boundary names a /corrections:codify call with that rule, and no entry says to add the rule to CLAUDE.md, AGENTS.md or a .claude/rules/ file. The run does not invoke codify, runs no extraction script, and writes or edits no CLAUDE.md, AGENTS.md or .claude/rules/ file."
---

/knowledge:course-digest analyze robust-http-apis-hale

The course is already extracted and Phases 3 and 4 are done: the module summaries and analysis/course-summary.md are in place, so no extraction script or browser is needed. Run Phase 5 for this repository and write its two files.
