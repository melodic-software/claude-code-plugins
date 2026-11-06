---
description: "Legacy setup case apply-interviews-and-writes-team-file-only, first turn. Narration: no MCP server loads in a run, so the prompt names the session's configured servers as facts. Before writing anything, apply presents the effective baseline across layers ahead of its first question (baseline-before-question), drafts a churn_exclude entry for the committed src/generated/ tree (drafts-generated-exclusion) and the declared acme-telemetry server as an evidence-source candidate (drafts-telemetry-candidate), asks with a recommendation (asks-with-recommendation), names no telemetry server the session does not have as an mcp_server value (no-undeclared-source), and makes no Write or Edit call, so no layer is written before the user answers (no-write, no-edit). Writing only the team file is unmeasured: the run's writes under the workspace .claude/ are denied, so the case grades what apply produces before that write. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [setup, apply, interview, narration, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: "The reply first shows the effective config (no layer present, bundled defaults), then drafts a churn_exclude entry for src/generated/ and an evidence_sources candidate for acme-telemetry, and asks the first interview question with a recommended answer. Nothing is written."
---

/improvement:setup apply

This session's configured MCP servers, take them as given: `acme-telemetry` (serves request metrics for the production web tier) and `github` (repository and pull request tools).
