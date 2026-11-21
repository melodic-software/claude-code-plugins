---
description: 'A dictated invocation ends the action word with a period: `rules.` must select the rules action, not the default action. The scaffold repository has an AGENTS.md with two rules, one package.json already states and one that needs judgment, so the ledger needs no proof run. A run needs --scaffold --allow-tools Bash Write.'
tags: ['codify', 'rules', 'routing', 'no-network']
allowed_tools: [Bash, Read, Glob, Grep, Skill, Write]
max_turns: 30
timeout_seconds: 600
expected_outcome: 'The trailing period is stripped from the first word, so the run is the rules action over AGENTS.md: both rules get an outcome in a ledger under .work/codify/ (npm test deleted as derivable from package.json, the naming rule kept as prose), and rules-ledger.mjs reconciles it. It does not count occurrences of a mistake described as "rules. AGENTS.md".'
---

/corrections:codify rules. AGENTS.md
