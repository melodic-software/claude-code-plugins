---
description: "Config seam with no config, SKILL.md 'Audit dimensions & targets': targets come from the config-cascade layers (team docs/conventions/codebase-health.md, the old .claude/codebase-health.md still read while it exists); when none is present, infer from the repo and persist the inference by offering /codebase-health:setup (the ladder's step 2); never hardcode a repo layout. Phase 0 resolves the config before discovery. The repo has no config file and no docs/ directory; README.md is its one documentation file. reports-config-absent grades that the reply says the config was not found, a bare `no docs/conventions/codebase-health.md`, `no .claude/codebase-health.md` or `no tracked config` included (worded so the config-gap section, which names the team file in every report, cannot satisfy it); config-lookup-first (llm, trace) that the run looked for the config before dispatching discovery; offers-setup that it offers /codebase-health:setup; no-config-write and no-config-edit that the audit writes no config itself (the offer is the persist step); no-hardcoded-layout (llm) that the audited targets come from this repository. Write and Edit are granted so the no-write graders can fail. Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, config-seam, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply says no codebase-health config (docs/conventions/codebase-health.md or another layer) was found, audits the documentation it inferred from this repository (README.md), and offers to persist the targets with /codebase-health:setup. No Write or Edit of a codebase-health config file."
---

/codebase-health:audit --docs-only
