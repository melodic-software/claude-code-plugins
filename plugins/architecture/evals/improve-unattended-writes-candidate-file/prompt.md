---
description: "Unattended deepening scan. A scaffolded repository holds a shallow pass-through chain and an admin route with no access check. The run writes the candidate file under the memory tier (candidate-file-written) with the five-field header (header-records-the-run) and a placeholder for the defect (security-placeholder-written), keeps the defect's detail out of the file (no-defect-detail-in-file) and the reply (reply-keeps-defect-private, llm), asks nothing (no-ask-tool), and writes no HTML report (no-html-report). The scaffolded repository has no origin, so the verification level resolves light. Needs --scaffold and --allow-tools Bash Write."
tags: [architecture, improve, unattended, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, AskUserQuestion]
expected_outcome: "Writes .work/architecture/improve/main/deepening-candidates-<stamp>.md with the unattended header and the pass-through chain as a candidate, records the admin defect only as a security-defect: withheld line, asks no question, and writes no HTML report."
---

/architecture:improve deepening --unattended
