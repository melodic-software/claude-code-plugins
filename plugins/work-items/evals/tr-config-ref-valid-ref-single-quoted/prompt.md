---
description: 'Legacy triage 24. A --config-ref of origin/main passes the check, so the settings come from that commit: the run passes the ref to parse-concern-value.sh single-quoted before the file argument, reports triage_repro_count=3 (repository), and ignores the checked-out branch''s 1. No tracker is bound, so the item is given in the prompt. pinned-read-single-quoted reads the Bash calls; settings-pinned and no-working-tree-value read the reply. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [triage, config-ref, settings]
max_turns: 30
timeout_seconds: 720
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The run accepts origin/main after checking it, runs parse-concern-value.sh with --ref ''origin/main'' single-quoted before the file argument, gets 3, and reports triage_repro_count=3 (repository), not the working-tree 1.'
---

/work-items:triage --config-ref origin/main 219

Autonomous lane whose standing directive authorizes triage label and comment mutations. #219 is a raw bug report: 'date picker shows the wrong week number in January'. Its steps: `python3 picker/week.py 2027-01-01` should print 53 and prints 0. At origin/main, docs/conventions/work-items.yaml sets triage_repro_count: 3; the checked-out branch's copy sets it to 1.

No tracker is bound in this checkout, so the item text above is what reading the item returns.
