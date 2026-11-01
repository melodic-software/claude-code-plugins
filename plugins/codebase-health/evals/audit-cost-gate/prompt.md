---
description: "Cost gate, SKILL.md lines 211-214 (and context/discovery-method.md step 2): with --docs-only but no path scope, the documentation dimension enumerates 33 files (README.md plus 32 pages under docs/), past the ~20-file line, so the run confirms with the user before dispatching any discovery subagent, and no report is presented (a full report would end with the setup offer of lines 298-301, which the ask grader alone could mistake for the scope ask). Agent is in allowed_tools (the plugin-evals Grant tools section lists it in the read-only set), so the no-dispatch grader can fail. AskUserQuestion is left out so the ask lands in the reply text. Needs --scaffold."
tags: [codebase-health, audit, outcome, cost-gate]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "The reply asks the user to confirm or narrow the scope, presents no audit report (no Verified non-issues section, findings table header, or no-findings verdict), and no Agent call is made."
---

/codebase-health:audit --docs-only

Check the docs for drift.
