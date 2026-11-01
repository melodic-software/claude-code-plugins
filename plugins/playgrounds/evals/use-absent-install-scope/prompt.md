---
description: "Slash-invoked with the upstream plugin absent, as in every eval run: Step 3 (SKILL.md lines 65-78) prints the marketplace-qualified install command and the scope guidance (user scope everywhere, project scope one repository), and no explorer is built in its place (lines 18-19 and 147-148). The presence check runs through the skill-listing fallback (lines 28-32), since Bash is not granted. The marketplace-add line is not graded (lines 72-74 against 78-79)."
tags: [playgrounds, use, outcome, install]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply prints `/plugin install playground@claude-plugins-official`, distinguishes user scope from project scope, and contains no HTML explorer."
---

/playgrounds:use an interactive explorer for our API's rate-limit settings: requests per minute, burst size and the cooldown window
