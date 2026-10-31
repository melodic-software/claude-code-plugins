---
description: "Ported from plugins/knowledge/skills/course-digest/evals/evals.json id 3. Written from MB:plugins/knowledge/skills/course-digest/SKILL.md:26,30-34,36-44 and MB:plugins/knowledge/skills/course-digest/templates/checklist.md:3. Covers lost sentences 41, 45, 46 (browser-tool prerequisite: the reply never names the claude-in-chrome MCP or a tabs_context_mcp preflight) and 42, 43, 60 (checklist path: any checklist written lands at .work/<slug>/course-digest-checklist.md with a kebab slug of at most 40 characters, though the URL's last segment is 43). The browser-tool expectation is head-side; a base failure is the old contract, so the no-chrome-mcp grader is tagged contract-change; the checklist-path and stop graders are outcomes both versions share. In the sandbox the plugin data directory is empty and setup-deps needs the network, so the course-extraction deps read MISSING and both versions stop at prerequisites before Phase 1; the Phase 1 module gate, instructor read and sequential Phase 2 of id 3 need a live browser and are not graded. Visibility: the scaffold runs git init with no remote, so head reads local and passes its gate"
tags: [knowledge, course-digest, outcome, scaffold, stop-gate, contract-change]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports which prerequisite is missing or failed and stops before course discovery, without naming the claude-in-chrome MCP or a tabs_context_mcp preflight as a prerequisite. No extraction script runs, and any phase checklist written sits at .work/<slug>/course-digest-checklist.md with a slug of at most 40 characters."
---

/knowledge:course-digest https://dometrain.com/course/getting-started-with-model-context-protocol/
