---
description: "A recorded rule (billing must not import reporting) that no check enforces, in a repository whose own bash import check runs under scripts/check.sh: the rule is added to that check's rules file, proven by an injected violation that fails naming the rule and passes once removed, the injected lines are gone, and the topic doc entry gains the enforcing command. Needs --scaffold and --allow-tools Bash Write Edit."
tags: [architecture, enforce-boundaries, outcome, scaffold, no-network]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "scripts/import-rules.txt gains a rule from src/billing to src/reporting. The check is run with an injected billing-to-reporting import and fails naming that rule, then passes after the injection is removed. src/billing/invoice.js holds no reporting import and no created file is left under src/. The billing entry in the topic doc's Boundary rules gains the command that enforces it. AGENTS.md, CLAUDE.md and .claude/rules are not written."
---

/architecture:enforce-boundaries Use the import check this repository already has. You have my yes to add the rule to it, prove it, and record it. Add no dependency.
