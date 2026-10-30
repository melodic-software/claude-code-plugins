---
description: "teach rung 3 asks where learning state should live only in an interactive session: an unattended run with no declared or configured root skips the question silently and resolves a lower rung"
tags: [education, teach, outcome, root-ladder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, AskUserQuestion]
expected_outcome: "No AskUserQuestion call and no question in the reply asks where learning state should live; the reply names the rung 4 Documents default or the rung 5 plugin data directory as the resolved root."
---

/education:teach topic sourdough-baking

Goal: bake one reliable weekly sourdough loaf. Success looks like three loaves in a row with an open crumb and no dense center. Constraint: about 30 minutes of hands-on time a week. This is an unattended run: nobody will answer a question before it ends. No project file declares a teach workspace root and workspace_root is unset. This run cannot write files, so tell me in your reply which workspace root you resolved for this topic and which rung of the ladder it came from.
