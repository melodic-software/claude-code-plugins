---
description: "Hard. A narrowed pass over the config lane uses the run mechanics scripts, not hand-built state: SKILL.md Phase 0, 'Do not derive the run directory or hand-write the lease. scripts/run-state.sh does both' (paths and lease acquire, each with --plugin-data); Phase 3, the config lane invokes /harness-config:audit via the Skill tool and every record goes through finding-identity.sh guarded-append; Phase 6, every run emits one line naming --opinion; bare invocation writes nothing into the target. Hard because the mechanics are long and a model tends to buffer findings or write state by hand. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write."
tags: [hard, audit-pass, outcome, run-state, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Agent]
expected_outcome: "run-state.sh paths and lease acquire run with --plugin-data; /harness-config:audit is invoked through the Skill tool; at least one finding goes through finding-identity.sh guarded-append; the reply names --opinion; no Write touches the target's settings, .mcp.json, CLAUDE.md or SKILL.md files."
---

/harness-config:audit-pass --lanes config
