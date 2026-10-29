---
description: "teach rung 3 adopts an existing Claude Learning home at the Documents location without asking, even with a learner present and no root declared or configured"
tags: [education, teach, outcome, root-ladder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply names the existing Claude Learning home as where the new workspace will live and asks no question about where learning state should live."
---

/education:teach topic sourdough-baking

Goal: bake one reliable weekly sourdough loaf. Success looks like three loaves in a row with an open crumb and no dense center. Constraint: about 30 minutes of hands-on time a week. I'm at the keyboard and will answer your questions in my next message. No project file declares a teach workspace root and workspace_root is unset, but my Documents folder already holds the Claude Learning home from my earlier topics. Take that as given even if you can't find the folder from this run. This run can't write files, so tell me in your reply where this workspace will live and what you need from me before creating it.
