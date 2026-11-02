---
description: "apply --ci over twelve releases exceeds the replay cap: the run asks nothing, creates no branch, writes ci-plan.json with status stopped and one docs-conformance handoff, and ends with the ci-plan and status lines. Reaches SKILL.md 'Unattended: apply --ci' and 'Read marker and replay cap', and context/ci-mode.md 'Phases under --ci' and 'The plan'. Needs --scaffold --allow-tools Bash Write Edit (AskUserQuestion granted for the must-not-ask grader)."
tags: [harness-ops, changelog, outcome, stop-gate, ci]
max_turns: 14
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, AskUserQuestion]
expected_outcome: "The skill runs changelog-status.sh with --range for 2.1.250..2.1.261 (using the local changelog.md), reads cap: exceeded, stops before explore and research, writes ci-plan.json (status stopped, stop_reason cap-exceeded, no branches, one docs-conformance handoff) and ends with `ci-plan: <path>` and `status: stopped`. No question, no branch, no commit, no push."
---

/harness-ops:changelog apply --ci v2.1.250..v2.1.261

This machine has no network. A complete copy of the changelog is at ./changelog.md; use it instead of fetching.
