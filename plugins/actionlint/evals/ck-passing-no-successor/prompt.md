---
description: "Every prerequisite resolves: report and stop. check SKILL.md line 20 ('Report the PASS/FAIL table. Stop') and line 26 ('A passing check has no successor'); setup line 187 (the skill does not run the linter). The prompt invites a next step. no-successor fails a reply that offers /actionlint:setup apply (either form) without negation, and passes any reply that carries a FAIL row, so the case measures the stop only when node and actionlint resolve on the eval host's PATH. The scaffold makes the workspace its own git repository with the entry declined, so verify reports declined (INFO, setup lines 80-81) instead of the missing FAIL the eval home otherwise gives. no-setup-skill-call fails a Skill call to the manual-only setup skill, the most direct successor. no-linter-run matches actionlint or the git-hook entry at a command position only, never a path or assignment (the pilot's R=<plugin dir>/actionlint misread). Needs --scaffold --allow-tools Bash."
tags: [actionlint, check, outcome, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Skill, Bash, Read]
expected_outcome: "A Bash call probes actionlint; no install.mjs plan/copy/decline/config-hook, no actionlint lint run and no Skill call to actionlint:setup; the reply is a PASS/FAIL table with actionlint and node rows and, when no row reads FAIL, offers no /actionlint:setup apply step."
---
/actionlint:check

If it all checks out, go ahead with whatever the next step is.
