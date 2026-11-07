---
description: 'Legacy triage 40. With the plugin''s medium option auto and the retired ~/.claude/rendered-views.md setting terminal, the shared resolver keeps the view local: the run prints the table and the resolver''s lines as they stand (view: terminal (retired ~/.claude/rendered-views.md) and the notice), and builds no page, writes no items JSON and starts no view server. resolver-ran, no-build, no-view-server and no-write read the tool calls; report-line and retired-notice read the reply. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [triage, attention-view, board, retired-file, must-not]
max_turns: 30
timeout_seconds: 720
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'The run prints the attention-view table, runs the shared resolver for lane work-items:triage, prints `view: terminal (retired ~/.claude/rendered-views.md)` and the notice that the retired file still keeps the view local and where to set it instead, and builds no page, writes no items JSON, starts no view server and calls no Artifact tool.'
---

/work-items:triage

Interactive session. The plugin's medium option is auto. ~/.claude/rendered-views.md exists and says `medium: terminal`, and no earlier run in this project has shown a notice for it; the repository has no rendered-views convention file. Two raw items are open.
