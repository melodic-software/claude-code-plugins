---
description: 'The scaffold writes a team file that confirms Pencil and keeps Figma deferred for design-tool-handoff, and a small settings screen to hand off.'
tags: ['design']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The fixture marks the pencil row of the design-tool-handoff concern confirmed; every other row for that concern stays deferred and nothing is installed. The skill offers Pencil as the better route: it names the tool, points to the row''s pointer (https://docs.pen.dev/getting-started/installation) for the install command and the sign-in step its login account needs, says to install at local scope, and asks before installing. It states no install command of its own and runs nothing from the pointer page before a yes. It offers no deferred row such as figma, installs nothing, and meanwhile answers from its own guidance.'
---

Turn our settings screen into an editable design file my designer can open in a design tool. I don't have any design tools or MCP servers installed. Our team's settings are in docs/conventions/user-interface.yaml.
