---
description: "Legacy clarify 11. The scaffold writes $HOME/.claude/rendered-views.md containing only 'medium: terminal' (refusing the real home) and no other rendered-views setting; history: the previous assistant message is Round 4 with three decisions. Run by hand on a first run the resolver prints 'view: terminal (retired ~/.claude/rendered-views.md)' and the notice that the file 'is retired but still keeps the view local ... set it in docs/conventions/rendered-views.local.yaml instead'. The skill runs the resolver, leaves the file to it, and keeps the table in the terminal (SKILL.md lines 83-101). resolver-ran (with-only); no-convention-read and no-convention-shell-read; retired-notice (both halves of the notice); report-line-retired; table-in-terminal (a decision table header in the reply); no-html-write and no-html-shell-write fail an HTML file written by Write or by a shell redirect. skill-fired is a with-only indicator. Watch: the resolver needs a real node on PATH, it shows a retired notice once per project per file content, and whether a run expands ${user_config.medium} is UNVERIFIED (see cl-resolver-default-decision-table). Needs --scaffold --allow-tools Bash; a history_file case runs single-arm, so pass --ablation with-without."
tags: [adhd, clarify, outcome, rendered-view, history, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Bash]
expected_outcome: "The resolver runs; no Read or Bash command names a rendered-views file; the reply prints 'view: terminal (retired ~/.claude/rendered-views.md)' and the retired-but-local notice naming where to set the value instead, and the decision table is in the reply, with no HTML file written."
---

clarify this.
