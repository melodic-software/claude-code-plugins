---
description: "Legacy clarify 10. The scaffold makes the workspace its own git repository with a tracked docs/conventions/rendered-views.yaml setting 'medium: artifact'; history: the previous assistant message is the dense Round 4 (four decisions). Run by hand in the scaffolded workspace the resolver prints 'view: auto (plugin default)' and 'notice: team docs/conventions/rendered-views.yaml sets medium: artifact; a team file never publishes, so it is ignored'. The skill runs the resolver and leaves every settings file to it (SKILL.md lines 83-97). resolver-ran (with-only) needs the resolver call; no-convention-read and no-convention-shell-read that no Read or Bash command names a rendered-views file; team-notice and report-line-plugin-default the printed lines; team-not-decider fails a report line naming the team file. skill-fired is a with-only indicator. Watch: the resolver needs a real node on PATH, and whether a run expands ${user_config.medium} is UNVERIFIED (see cl-resolver-default-decision-table). Needs --scaffold --allow-tools Bash; a history_file case runs single-arm, so pass --ablation with-without."
tags: [adhd, clarify, outcome, rendered-view, history, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Bash]
expected_outcome: "The resolver runs with --lane adhd:clarify; no Read or Bash command names a rendered-views file; the reply prints 'view: auto (plugin default)' and the notice that a team file never publishes, and no report line names the team file as what decided."
---

make this clear.
