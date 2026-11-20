---
description: "Medium. criteria.md C8 items 1-3 with a corrections stand-in loaded: a CLAUDE.md instruction a machine could check, which no check covers today and which is no protected rail, gets a WARN that it could move up the hierarchy, and when /corrections:codify is among the available skills the finding hands codify the choice of mechanism, naming the call, and the audit names no mechanism itself. Read-only; no audit runs. Bash is granted only because the skill's pre-computed spine line needs it to load. Hard because the obvious answer is to name the mechanism yourself (a lint rule or a CI check), which the changed item 3 leaves to codify. Source: issue 17200's host step for issue 17179, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [audit, harness-memory, enforcement, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "C8 is warn for the line. The MOVE line names a /corrections:codify call for the set -euo pipefail rule and does not say codify is unavailable; the MECHANISM line says none, since the audit leaves the mechanism to codify; the reply does not run codify."
---

Before we run /harness-memory:audit on our repo, I need to know how its C8 check treats one line
in our project CLAUDE.md:

"Every shell script under `scripts/` starts with `set -euo pipefail`."

Nothing checks this today: no hook, CI job, lint rule or test looks at it. It is a style rule, not
a security or destructive-action rail.

Load the `harness-memory:audit` skill with the Skill tool to read its rules, but don't run the
audit, research online or run any other command. Read its `reference/criteria.md`, check C8 items
1 to 3 (whether the line could move up the enforcement hierarchy, and where the move goes), and
tell me what the audit's finding for this line would say.

End your reply with exactly these three lines, filled in:

C8: <warn|none>
MOVE: <one line: where the audit's finding says this instruction's move goes>
MECHANISM: <the enforcement mechanism the audit itself names for this line, or none>
