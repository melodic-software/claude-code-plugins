---
description: 'Legacy work 19. CI mode on an issue whose wanted outcome and done check are both open: the run makes no edit and writes exit pushback with cause intent and the intent question in reason. pushback-intent reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, pushback]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The outcome and its done check are open, an intent question, so the run makes no edit and writes exit pushback with cause intent and a reason asking what better means and how to check it.'
---

/work-items:work --issue 700 --ci

Issue 700 says: "The lane report is confusing; make it better." Its Done when reads "the report is better", it names no reader, section or measure, and no comment the runner marked `"decision": true` answers what "better" means. What does the run do before any edit, and what does it write to work-outcome.json?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
