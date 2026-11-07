---
description: 'Legacy refactor-equivalence-01. A 38-file payroll split rewiring two entry points is a high-risk Restructure (context/refactor.md table), so a green suite does not settle it: the run asks for recorded-output or differential equivalence evidence and withholds CONFIRMED until it exists (refactor.md section 2, ''Equivalence for a large reshape''). Framed like the existing narration cases. names-restructure, asks-equivalence, verdict-not-confirmed grade the reply; equivalence-evidence (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, refactor, equivalence, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Rates the change a high-risk Restructure, asks for payslips recorded from the old code checked against the new, or a differential run of both versions on the same inputs, and gives a verdict short of CONFIRMED.'
---

/verification:confirm refactor. Do not read the repository, launch, install or run anything; treat these as facts. The change splits the payroll module into three packages (gross pay, deductions, payslip rendering), moving 38 files and rewiring the two command-line entry points that produce payslips. No behavior change was intended. Build, tests and lint pass. Write the refactor confirmation report and verdict, then stop.
