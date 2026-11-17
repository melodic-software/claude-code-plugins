---
description: 'The taste action on a silent edit. On branch feat/pricing an agent-written commit (Co-Authored-By: Claude) adds a pricing card with a heavy shadow, and the next commit, by the person, drops the shadow to 0 1px 3px rgba(0, 0, 0, 0.12) and renames the heading from Pro to Professional, giving no reason. The run must find the shadow edit in the branch history, keep it at the class level (raised surfaces or cards, not the pricing card alone), drop the heading rename as a one-off copy change, mark the reason inferred, and stop for confirmation and approval: the prompt approves nothing, so DESIGN.md must not be written. A run needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail).'
tags: ['codify', 'taste', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 25
timeout_seconds: 600
expected_outcome: 'The run reads the branch commits, proposes one class-level shadow rule with the value 0 1px 3px rgba(0, 0, 0, 0.12), marks its reason inferred and asks the person to confirm it and approve the rule, lists the heading rename as dropped, and writes no DESIGN.md and edits no file under src/.'
---

/corrections:codify taste. I fixed up the pricing card you made on this branch in my last commit.
