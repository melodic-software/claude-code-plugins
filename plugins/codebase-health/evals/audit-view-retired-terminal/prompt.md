---
description: "Rendered view with only the retired ~/.claude/rendered-views.md setting terminal, SKILL.md lines 325-353: resolve medium with the shared resolver (lines 335-340), print its report line and notices after the report as they stand (lines 342-343), leave the rendered-views files to the resolver (lines 343-345), and when medium is terminal make no offer and print no unavailable line (lines 330-331 and 351). The scaffold writes $HOME/.claude/rendered-views.md with 'medium: terminal' (refusing the real home) and no other rendered-views file; run by hand in the scaffolded workspace on a first run the resolver prints 'view: terminal (retired ~/.claude/rendered-views.md)' and the notice that the file is retired but still keeps the view local. The README carries one false claim so the report has a finding. The prompt states the interactive session in plain words, since line 329 skips the view section when no one is reading. view-line-after-report needs the resolver's line after the Verified non-issues section; retired-notice the notice text; resolver-ran (with-only) the resolver call; no-convention-read and no-convention-shell-read that no Read or Bash command names a rendered-views file; no-view-offer that the reply makes no offer and prints no unavailable line. Watch items: the resolver needs a real node on PATH in the sandbox, and line 339 passes the user_config.medium token through Bash. Needs --scaffold --allow-tools Bash."
tags: [codebase-health, audit, outcome, rendered-view, narration, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Bash]
expected_outcome: "The reply presents the report, then prints 'view: terminal (retired ~/.claude/rendered-views.md)' and the notice that ~/.claude/rendered-views.md is retired but still keeps the view local, and makes no rendered-view offer and no unavailable line. The resolver ran, and no Read or Bash command names a rendered-views file."
---

/codebase-health:audit README.md --docs-only

I'm reading along in this session.
