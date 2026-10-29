---
description: "teach rung 3 asks once where learning state should live when a learner is present, no root is declared or configured and no learning home exists yet, offering the Documents default. The run itself is claude -p, so the learner's presence rests on the prompt saying so; te-root-headless-skip is the same setup with nobody present"
tags: [education, teach, outcome, root-ladder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply asks exactly one question about where learning state should live and offers the Documents Claude Learning default (or names the Documents folder) as an answer."
---

/education:teach topic sourdough-baking

Goal: bake one reliable weekly sourdough loaf. Success looks like three loaves in a row with an open crumb and no dense center. Constraint: about 30 minutes of hands-on time a week. I'm at the keyboard and will answer your questions in my next message. No project file declares a teach workspace root, workspace_root is unset, and I have no Claude Learning folder or earlier learning workspaces anywhere. This run can't see my home folder or write files, so end your reply with what you need from me before the workspace is created.
