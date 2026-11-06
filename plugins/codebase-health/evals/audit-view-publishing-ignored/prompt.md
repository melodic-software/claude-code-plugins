---
description: "Rendered view where a tracked team file and the retired ~/.claude/rendered-views.md both set the publishing value artifact, SKILL.md lines 316-344: resolve medium with the shared resolver (lines 326-331), print its report line and notices after the report as they stand (lines 333-334), and leave the rendered-views files to the resolver, which never publishes on a team file's say-so (lines 334-336). Neither value decides, so medium is null, the offer row (line 343). Only this plugin loads in an eval run, so visualization:visualize is absent and lines 323-324 apply: say in one line that the optional view is unavailable, and never hand-build an HTML file or chart. Run by hand in the scaffolded workspace on a first run the resolver prints 'view: auto (plugin default)', the notice that ~/.claude/rendered-views.md is no longer read, and the notice that a team file never publishes. view-line-after-report needs the resolver's line after the Verified non-issues section; team-notice and retired-notice the two notices; view-unavailable-line the one unavailable line; resolver-ran (with-only) the resolver call; no-convention-read and no-convention-shell-read that no Read or Bash command names a rendered-views file; no-html-write that no .html or .svg file is written. The prompt states the interactive session in plain words, since line 320 skips the view section when no one is reading. Watch items: the resolver needs a real node on PATH in the sandbox, and line 330 passes the user_config.medium token through Bash. Needs --scaffold --allow-tools Bash Write."
tags: [codebase-health, audit, outcome, rendered-view, narration, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Bash, Write]
expected_outcome: "The reply presents the report, then prints 'view: auto (plugin default)', the notice that ~/.claude/rendered-views.md is no longer read and the notice that a team file never publishes, and says in one line that the optional view is unavailable. The resolver ran, no Read or Bash command names a rendered-views file, and no .html or .svg file is written."
---

/codebase-health:audit README.md --docs-only

I'm reading along in this session.
