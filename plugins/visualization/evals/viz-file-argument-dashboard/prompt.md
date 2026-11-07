---
description: "Legacy visualize 6. The explicit file argument goes to the shared medium resolver as --argument file (SKILL.md lines 114-125), which prints 'view: file (argument)' (run by hand outside a repository); the dashboard is then a self-contained local HTML file under a mktemp directory (lines 173-186) whose path is reported, and nothing is published. resolver-ran (with-only) needs the resolver call with --argument file, report-line the printed line, page-written a Write or shell write of an .html file, no-remote-asset and no-linked-asset that no written file or command carries a remote URL or a script src or stylesheet link (self-contained), reports-path an absolute .html path in the reply, no-artifact-link no claude.ai artifact link. Needs --allow-tools Bash Write."
tags: [visualization, visualize, outcome, rendered-view, no-network]
max_turns: 16
timeout_seconds: 480
allowed_tools: [Skill, Read, Write, Bash]
expected_outcome: "The resolver runs with --argument file and its line 'view: file (argument)' is printed; a self-contained HTML dashboard is written to a local temp file whose absolute path is reported; nothing is published."
---

/visualization:visualize file make a dashboard of the release metrics for this sensitive project: releases per week (W1 4, W2 6, W3 3, W4 7), median lead time in hours (W1 30, W2 26, W3 41, W4 22), change failure rate (W1 25%, W2 17%, W3 33%, W4 14%), rollbacks (W1 1, W2 1, W3 1, W4 1).
