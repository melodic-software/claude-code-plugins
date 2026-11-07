---
description: 'Legacy work 15. CI mode with a recorded decision to ship part A and keep the issue open: part B goes in remaining, not not_done, and part A stays out of it. remaining-names-part-b reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, linkage, decision]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The recorded decision keeps the issue open, so part B is named in remaining (for example ["Part B: migrate the callers to the new config key"]), which makes the PR link the issue without closing it. Part A is not in remaining, and part B is not put in not_done.'
---

/work-items:work --issue 633 --ci

Issue 633 has two parts: part A adds a config key, part B migrates the callers. A comment marked `"decision": true` says: "Decision recorded. Ship part A now; part B waits for the next release, so keep this issue open (keep Refs)." The run built part A, committed it, and every check passed. What does the run write in work-outcome.json for the work it left?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
