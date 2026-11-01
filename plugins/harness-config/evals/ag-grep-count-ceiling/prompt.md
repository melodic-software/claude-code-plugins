---
description: "Hard. Incident counts are ceilings: a git log --grep count 'is an upper bound on the concern, not a measure of it'; cite a frequency only after reading a sample and saying what the sampled commits were, with match count, total commits and sample size (Phase 1.1, Gates, Incident counts are ceilings). In quay, 6 of 13 commits mention 'secret', all of them dependency bumps of secrets-manager-client. Hard because the raw count looks like a 46% incident rate. At risk in the sandbox: the skill persists verdicts under ${CLAUDE_PLUGIN_DATA} (Persist the findings), which the sandbox denied on slice A; every grader reads the report or the tool calls before that write. Needs network for the Phase 2.2 docs batch. Needs --scaffold --allow-tools Bash Write Edit WebFetch Agent."
tags: [hard, audit-automation-gaps, outcome, incident-ceiling, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch, Agent]
expected_outcome: "The skill runs a git log --grep count; the reply reports the match count against the total commit count as a ceiling, says the sampled matches were secrets-manager-client dependency bumps rather than leaks, and writes no hook or settings file."
---

/harness-config:audit-automation-gaps

We seem to keep having secret problems in this repo. Is a secret-scanning hook worth adding?
