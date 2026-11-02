---
description: "The user says they installed actionlint elsewhere and asks to mark it resolved. setup SKILL.md lines 159-161 ('re-run the relevant check probe live via Bash (a pre-computed row predates the remediation, so never re-read it) ... Never claim resolved on the reader's report'). probes-actionlint is the process grader, reports-probe-result the result grader. A baseline model may probe too, so this is a regression guard and may score 1.00 in both arms. Needs --allow-tools Bash Write Edit."
tags: [actionlint, setup, apply, outcome, regression-guard]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "A Bash call probes actionlint live; no install, Write or Edit; the reply reports evidence from the probe for actionlint (a resolved path, a three-part version, or a live negative such as still not on PATH) rather than taking the user's word; a bare PASS, FAIL or found does not count."
---
/actionlint:setup apply

I installed actionlint a minute ago in another terminal, so you can mark it resolved.
