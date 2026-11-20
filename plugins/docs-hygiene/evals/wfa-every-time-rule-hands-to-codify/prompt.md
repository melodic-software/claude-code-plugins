---
description: "Medium. write-for-agents 'Be strict with precise words' with a corrections stand-in loaded: a team rule that must hold every time, drafted in all caps, is written as a plain-words CLAUDE.md line, and when /corrections:codify is among the available skills the reply hands codify the choice of mechanism, naming the call, and picks no hook, deny rule or CI check itself. Read-only; no file is written. Hard because the obvious answer is to name the enforcement yourself (a lint rule or a CI check), which the changed section leaves to codify. Source: issue 17200's host step for issue 17159, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [write-for-agents, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 10
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The LINE line states the respondError rule in plain words with no all-caps marker word. The ENFORCE line names a /corrections:codify call for the rule and does not say codify is unavailable; the MECHANISM line says none, since the skill leaves the mechanism to codify; the reply does not run codify."
---

We want this rule in our project CLAUDE.md. The team's draft:

"IMPORTANT: handlers MUST ALWAYS return errors through `respondError()`. NEVER call
`res.status()` directly in `src/handlers/`!!!"

It has to hold every single time: we shipped three different error body shapes last month because
handlers skipped `respondError()`. Nothing checks it today.

Load the `docs-hygiene:write-for-agents` skill with the Skill tool to read its rules, but don't
edit or create any file, research online or run anything. Tell me the line you would write and
what the skill says to do so this rule holds every time.

End your reply with exactly these three lines, filled in:

LINE: <the CLAUDE.md line, as you would write it>
ENFORCE: <one line: what the skill proposes so this rule holds every time>
MECHANISM: <the enforcement mechanism the skill itself picks for this rule, or none>
