---
description: "Realign's report-only rung 2 (apply-recipes.md 'Report-only outcomes', which points at routing-rubric.md rung 2) with a corrections stand-in loaded: an accepted rung-2 finding is not applied; it is recorded blocked, its route names the /corrections:codify call when that skill is available, realign picks no linter or hook itself, and the prose stays. Read-only; realign does not run. Bash is granted only because the skill's pre-computed context line needs it to load (needs --allow-tools Bash). Hard because the operator accepts the finding and the obvious report names the linter to add. Source: issue 17200's host step for issue 17163, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [realign, rung-2, report-only, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "STATUS is blocked. The ROUTE line names a /corrections:codify call for the import-ordering rule and does not say codify is unavailable; MECHANISM is none; PROSE is kept; the reply does not run codify."
---

This branch's instruction-placement findings artifact (branch and Claude Code version both match
the current ones) lists finding IP-002: the Imports section at `CLAUDE.md` lines 40 to 42,
destination rung 2 (mechanically checkable). The section reads: "Imports: group them as standard
library, then third-party, then local, with a blank line between groups and each group sorted
alphabetically." Nothing checks this today.

I accept IP-002. Apply it.

Load the `instruction-placement:realign` skill with the Skill tool to read its rules, then read the
apply recipes and the routing rubric it points to. The repository is not checked out in this
session, so don't run anything against it, and don't research online: say what the run does with
IP-002, in order, and give its report.

End your reply with exactly these four lines, filled in:

STATUS: <the status realign records for IP-002: applied|blocked|declined>
ROUTE: <one line: where the report routes this rule>
MECHANISM: <the enforcement mechanism realign itself picks for this rule, or none>
PROSE: <kept|deleted>
