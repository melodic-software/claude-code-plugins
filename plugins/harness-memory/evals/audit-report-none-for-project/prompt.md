---
description: 'Legacy audit 6. The report action on a project with no saved audit: it runs the state-key resolver, looks at this project''s derived path, finds nothing, says no audit has been run for this project and suggests one, and fabricates nothing or reads an unkeyed file. runs-resolver reads the trace and none-for-this-project the reply. Bash is granted because the resolver is a script. Routine: the empty report path.'
tags: [audit, harness-memory, report, routine]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The run executes lib/state-key.sh to derive the key, looks for audit/<state-key>/last-audit.md under the plugin data directory, finds nothing, and the reply says no audit has been run for this project, suggests running one, and presents no findings from anywhere else.'
---

/harness-memory:audit report Show me the memory health report. I want to see the last results. No one is around to answer questions while this runs, so put the answer in your reply.
