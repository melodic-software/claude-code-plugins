---
description: "A Go module with a recorded entry-points-only rule for billing (no package outside billing imports billing/ledger): asked for the plan first, the run plans the boundary the Go build already enforces (an internal package under billing) over a separately run lint, script or architecture-test tool, and writes nothing. Needs --scaffold and --allow-tools Bash Write Edit."
tags: [architecture, enforce-boundaries, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "No Write or Edit call. The plan enforces the billing rule by making the ledger a Go internal package of billing (billing/internal/ledger), so the compiler refuses an import from outside billing, and chooses that over adding a separately run check; it asks before moving the package."
---

/architecture:enforce-boundaries Show me your plan for enforcing our boundary rule before you change anything.
