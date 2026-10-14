---
description: "A diff over twelve releases exceeds the replay cap: the skill runs the status script on the range, stops, relays the docs-conformance recheck and marker-reset recommendation, and emits no decision rows and spawns no research agents. Reaches SKILL.md 'Read marker and replay cap', 'Action: apply' Phase 0 step 2 (shared by diff) and 'Actions: fetch, diff, status'. Needs --scaffold --allow-tools Bash Write Edit (Agent granted for the must-not-spawn grader)."
tags: [harness-ops, changelog, outcome, stop-gate]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Agent]
expected_outcome: "The skill runs changelog-status.sh with --range for 2.1.250..2.1.261 (using the local changelog.md), reads cap: exceeded, stops before explore and research, and relays the recommendation: a docs-conformance recheck of the components, then a read marker set at 2.1.261. No decision-row table, no subagent spawned."
---

/harness-ops:changelog diff v2.1.250..v2.1.261

This machine has no network. A complete copy of the changelog is at ./changelog.md; use it instead of fetching.
