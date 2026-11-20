---
description: "Medium. routing-rubric.md rung 2 through the audit, with a corrections stand-in loaded: a CLAUDE.md line a machine could check (import ordering) lands on rung 2, and when /corrections:codify is among the available skills the finding hands codify the choice of mechanism, naming the call, picks no linter or hook itself, and keeps the prose. Read-only; no audit runs. Bash is granted only because the skill's pre-computed context line needs it to load (needs --allow-tools Bash). Hard because the obvious answer is to name the linter yourself, which the changed rung 2 leaves to codify. Source: issue 17200's host step for issue 17163, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [audit, rung-2, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "RUNG is 2. The ROUTE line names a /corrections:codify call for the import-ordering rule and does not say codify is unavailable; MECHANISM is none; PROSE is kept until the mechanism exists; the reply does not run codify."
---

Before we run the instruction-placement audit on our repo, I need to know what it would find for
one section of our project CLAUDE.md:

"Imports: group them as standard library, then third-party, then local, with a blank line between
groups and each group sorted alphabetically."

Nothing checks this today. It is not a safety rail, and an agent cannot work it out from the code,
since the existing files are not consistent.

Load the `instruction-placement:audit` skill with the Skill tool to read its rules, but don't run
the audit, research online or run any other command. Read the routing rubric it points to, walk
this section down the decision ladder, and tell me what the audit's finding would say.

End your reply with exactly these four lines, filled in:

RUNG: <the decision-ladder rung number this section lands on>
ROUTE: <one line: where the finding routes this rule>
MECHANISM: <the enforcement mechanism the audit itself picks for this rule, or none>
PROSE: <kept|deleted>
