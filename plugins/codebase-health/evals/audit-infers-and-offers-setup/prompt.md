---
description: "Config seam with no config, SKILL.md lines 108-139: targets come from the tracked .claude/codebase-health.md layers (lines 114-116); when it is absent, infer from the repo and persist the inference by offering /codebase-health:setup (lines 131-133); never hardcode a repo layout (line 139). Phase 0 resolves the config before discovery (lines 192-193). The repo has no config file and no docs/ directory; README.md is its one documentation file. reports-config-absent grades that the reply says the config was not found, a bare `no .claude/codebase-health.md` or `no tracked config` included (worded so the config-gap section, which names .claude/codebase-health.md in every report, cannot satisfy it); config-lookup-first (llm, trace) that the run looked for the config before dispatching discovery; offers-setup that it offers /codebase-health:setup; no-config-write and no-config-edit that the audit writes no config itself (the offer is the persist step); no-hardcoded-layout (llm) that the audited targets come from this repository. Write and Edit are granted so the no-write graders can fail. Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, config-seam, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply says no .claude/codebase-health.md config was found, audits the documentation it inferred from this repository (README.md), and offers to persist the targets with /codebase-health:setup. No Write or Edit of a codebase-health config file."
---

/codebase-health:audit --docs-only
