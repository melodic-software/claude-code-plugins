---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Proposes the owner rule as a boundary rule in the forbidden-reference form (every project other than Billing.Ledger must not reference Billing.Ledger.Data), with its manifest evidence. On the yes it announces the path, appends a ## Boundary rules section to docs/conventions/architecture/README.md holding one entry with the rule, its evidence and the date, leaves the YAML block and other prose unchanged, reads the file back and reports the line, and points at /architecture:improve boundaries.'
---

/architecture:improve conventions. The convention home resolves to docs/conventions and docs/conventions/architecture/README.md exists with an architecture_dir key and no Boundary rules section. Billing.Ledger.Data is referenced only by Billing.Ledger: Billing.Ledger.csproj line 9 and no other project manifest references it. When you propose a rule for it, I say yes.
