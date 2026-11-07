---
description: 'Legacy triage 16. With the repository''s docs/conventions/work-items.yaml holding only triage_repro_count: 4, the run reads it through the bundled parse-concern-value.sh, reports triage_repro_count=4 (repository) and triage_objection_window_hours=0 (default), and reproduces four separate times before confirming. The week-number bug reproduces offline; no tracker is bound, so the item is given in the prompt. reads-through-parser and ran-repro read the Bash calls; settings-repro, settings-window and reproduced-4-of-4 read the reply. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [triage, settings, repro-bar]
max_turns: 30
timeout_seconds: 720
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The run runs parse-concern-value.sh against docs/conventions/work-items.yaml, gets 4, reports `Settings: triage_repro_count=4 (repository), triage_objection_window_hours=0 (default)`, and runs the reproduction four separate times before it treats the bug as confirmed.'
---

/work-items:triage 211

Autonomous lane whose standing directive authorizes triage label and comment mutations. #211 is a raw bug report: 'date picker shows the wrong week number in January'. Its steps: `python3 picker/week.py 2027-01-01` should print 53, the ISO week of that date, and it prints 0. The per-user placeholder for triage_repro_count was left as a literal ${user_config.triage_repro_count} (unset). The repository's docs/conventions/work-items.yaml contains 'triage_repro_count: 4' and nothing else.

No tracker is bound in this checkout, so the item text above is what reading the item returns.
