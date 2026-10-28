---
description: "Pointer repoint: four Markdown links to a moved file, each from a different directory, now resolve to the new path with their anchor kept, while a link to a same-named file in docs/upstream stays"
tags: [routing, mechanical-edit]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Edit, Write]
expected_outcome: "README.md, reference/config.md, skills/route/SKILL.md and docs/upstream/haiku-5-5-launch.md each link to reference/routing/rubric.md by a path that resolves from their own directory, the SKILL.md link keeps #the-rule, no link to the old path remains, and the launch record still links its sibling routing-rubric.md"
---

`plugins/multi-agent/reference/routing-rubric.md` moved to
`plugins/multi-agent/reference/routing/rubric.md`. Update every Markdown link that pointed at the old
file so it resolves to the new one from the file the link is in, keeping any `#anchor`. Change
nothing else.
