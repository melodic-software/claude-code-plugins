---
description: "An unattended run on a repository with an import check and a recorded rule no check enforces: the run stops after the plan, reports the mechanism it would use for the billing rule, and writes, edits and injects nothing. Needs --scaffold and --allow-tools Bash Write Edit."
tags: [architecture, enforce-boundaries, outcome, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "No Write or Edit call and no shell write. scripts/import-rules.txt and src/billing/invoice.js are unchanged. The reply gives the plan for the billing-must-not-import-reporting rule (add it to the existing import check run by scripts/check.sh) and says nothing was written because no one can approve it."
---

/architecture:enforce-boundaries This is a scheduled unattended run. No one will read or answer questions until tomorrow.
