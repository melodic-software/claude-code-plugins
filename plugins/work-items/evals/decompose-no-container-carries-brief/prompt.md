---
description: "With no spec container, each published item body carries the PLAN.md Brief's Goal and Constraints inline and names no memory-slice path. A run needs --scaffold and --allow-tools Bash,Write."
tags: [decompose, intent-chain]
runs: 3
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Drafts vertical-slice items from the plan phases and publishes them through create-item as plain items with no spec container; each published item body carries the Brief's Goal (reconcile refunds against the bank statement) and both Constraints (nightly ledger job untouched, reporting replica only) as text, and no body names a .work/ path"
---

/work-items:decompose

The topic is refund-export and its PLAN.md is approved. I approve the breakdown you draft in advance:
publish it as plain items with no spec container, without stopping to ask me anything.
