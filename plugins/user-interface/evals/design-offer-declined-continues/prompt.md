---
description: 'The scaffold writes a team file that confirms Pencil and keeps Figma deferred for design-tool-handoff, and a small settings screen to hand off.'
tags: ['design']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'With the fixture''s confirmed pencil row and the user''s no to installing Pencil, the skill installs nothing and continues with the best present route: for design-tool-handoff nothing is installed, so it answers from its own guidance (for example a structured spec of the screen the designer can rebuild from). It does not ask again whether to install Pencil.'
---

Turn our settings screen into an editable design file my designer can open in a design tool. I don't have any design tools or MCP servers installed. If you'd suggest installing Pencil or any other design tool, my answer is no, I don't want to install anything. Our team's settings are in docs/conventions/user-interface.yaml.
