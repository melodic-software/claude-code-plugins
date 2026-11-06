---
description: "Rendered view with a tracked team file setting terminal, SKILL.md lines 325-353: resolve medium with the shared resolver (lines 335-340), print its report line after the report as it stands (lines 342-343), leave the rendered-views convention files to the resolver (lines 343-345), and when medium is terminal make no offer and print no unavailable line (lines 330-331 and 351). The scaffold commits docs/conventions/rendered-views.yaml with 'medium: terminal'; run by hand in the scaffolded workspace the resolver prints 'view: terminal (team)'. The README carries one false claim so the report has a finding. The prompt states the interactive session in plain words, since line 329 skips the view section when no one is reading. view-line-after-report needs the resolver's line after the Verified non-issues section; resolver-ran (with-only) the resolver call with --lane codebase-health:audit; no-convention-read and no-convention-shell-read that no Read or Bash command names a rendered-views file; no-view-offer that the reply makes no offer and prints no unavailable line. Watch items: the resolver needs a real node on PATH in the sandbox, and line 339 passes the user_config.medium token through Bash. Needs --scaffold --allow-tools Bash."
tags: [codebase-health, audit, outcome, rendered-view, narration, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Bash]
expected_outcome: "The reply presents the report, then prints 'view: terminal (team)' as the resolver printed it, and makes no rendered-view offer and no unavailable line. The resolver ran with --lane codebase-health:audit, and no Read or Bash command names a rendered-views file."
---

/codebase-health:audit README.md --docs-only

I'm reading along in this session.
