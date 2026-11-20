---
description: "Medium. design's 'Codify rules when discovered' key behavior (and Phase 5 step 4) with a corrections stand-in loaded: a project-wide principle surfaced in design discussion is handed to /corrections:codify, naming the call, and the skill writes no rules-file line for it and picks no mechanism itself. Read-only; no design session runs. Hard because the obvious answer is to add the principle to the project's rules files, which the changed text leaves to codify. Source: issue 17200's host step for issue 17174, in the shape of session-flow's re-mechanical-finding-check-proposal."
tags: [design, outcome, codify-handoff, hard]
plugins: ["../..", "corrections-stub"]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The ROUTE line names a /corrections:codify call for the principle that domain code never imports the infrastructure package. It does not say the skill adds the principle to CLAUDE.md, AGENTS.md, .claude/rules or another rules file, does not say codify is unavailable, and the reply does not run codify."
---

We are midway through a module design for our orders service. In the last discussion round the
team agreed on a principle that holds for every service in the repository, not only this one:

> Code under `domain/` never imports from `infrastructure/`; adapters depend on the domain, never
> the other way round.

Nothing in the repository states or checks that today.

Before we continue with /planning:design, I need to know what the skill does with a principle like
this. Load the `planning:design` skill with the Skill tool to read its rules, but don't run a design
session, research online or run anything. Read what it says about project-wide principles that
discussion surfaces (its discussion rounds and its key behaviors), and tell me what it would do
with this one.

End your reply with exactly this line, filled in:

ROUTE: <one line: what the design skill does with this principle>
