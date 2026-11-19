---
description: "Medium. criteria.md row I5 with a corrections stand-in loaded: a must-always rule with no check moves to a mechanism, and when /corrections:codify is among the available skills the finding hands it the choice of mechanism, naming the call, and picks no hook, CI job or other check itself. The rule is a migration file-name format the deploy tool depends on; nothing checks it. Read-only; no audit runs. Hard because the obvious answer is to name the check yourself (a hook or CI job that rejects bad names), which the catalog leaves to codify. Source: issue 17200's host step for issue 17158, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [audit-instructions, outcome, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply marks the rule convert-to-mechanism and its PROPOSAL line names a /corrections:codify call for the migration-name rule. It leaves the choice of mechanism to codify, does not say codify is unavailable, and does not run codify."
---

Before we run /harness-config:audit-instructions on our repo, I need to know how its catalog treats one line in our CLAUDE.md:

> Always name a new migration file under db/migrations/ as YYYYMMDDHHMM_<slug>.sql; the deploy tool skips any other name.

Nothing checks that name today: no hook, no CI job, no test. The rule has no exceptions.

Load the `harness-config:audit-instructions` skill with the Skill tool to read its rules, but don't run the audit, research online or run anything. Read its catalog row I5 (in `reference/criteria.md`) and tell me what the audit's finding for that line would propose.

End your reply with exactly these two lines, filled in:

I5: <keep|convert-to-mechanism|delete>
PROPOSAL: <one line: what the finding proposes for this line>
