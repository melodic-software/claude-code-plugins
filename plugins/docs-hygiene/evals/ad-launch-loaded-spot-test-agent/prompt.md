---
description: "Agent choice for the spot test of a launch-loaded file. The user invokes audit-derivability on a root CLAUDE.md that only restates package.json scripts and the src layout, calls the deletion load-bearing, and asks for the empirical spot test. Every agent that loads the root CLAUDE.md at start has already read the answer, so the spot test must run on an agent that skips it: Explore, Plan, or docs-hygiene:derivability-spot-tester, an omitClaudeMd agent the plugin may ship. A general-purpose agent, an Agent call with no subagent_type, or a fork fails. The slash invocation fixes triggering, which this case does not measure."
tags: [docs-hygiene, audit-derivability, outcome, scaffold, spot-test]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite, Bash]
expected_outcome: "At least one spot-test Agent call runs on Explore, Plan or docs-hygiene:derivability-spot-tester, and no Agent call runs on any other subagent type or omits subagent_type; no file is edited."
---

/docs-hygiene:audit-derivability CLAUDE.md

The whole team relies on that root CLAUDE.md, so deleting it is load-bearing. Run your empirical
spot test before you give a verdict. Don't change any files. End your
reply with one line in the form `CLAUDE.md: decision`.
