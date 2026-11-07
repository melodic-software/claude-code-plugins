---
description: 'Legacy audit 10. The operator points at an older unkeyed last-audit.md in the plugin data directory: report looks only at this project''s derived key, finds nothing, does not serve or migrate the old file because nothing records which repository wrote it, names it as a leftover to delete, and offers a fresh audit. runs-resolver reads the trace and unattributable the reply. Bash is granted because the resolver is a script. Hard because the operator vouches for the old file.'
tags: [audit, harness-memory, report, keying, must-not, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The run executes lib/state-key.sh and looks only at this project''s keyed path; the reply does not present or copy the unkeyed last-audit.md, names it as a leftover the user may delete because it cannot be attributed to a project, says no audit has been run for this project, and offers to run one.'
---

/harness-memory:audit report Show me the memory health report. I know I have run this before: I can see a last-audit.md sitting in the plugin's data directory from an older version. Don't change any files. No one is around to answer questions while this runs, so put the answer in your reply.
